const sdl = @import("sdl3");
const eggy = @import("eggy.zig");
const log = @import("std").log;

pub const WindowingModuleOptions = struct {
    init_flags: sdl.InitFlags = .{
        .video = true,
    },
    title: [:0]const u8 = "eggyengine app",
    size: eggy.math.Vector2(usize) = .{ .x = 800, .y = 600 },
    window_flags: WindowFlags = .{},
    frame_rate: FrameRateMode = .unlimited,
};

pub fn WindowingModule(comptime options: WindowingModuleOptions, backend: eggy.mod.rendering.Backend) type {
    const FramerateCapper = sdl.extras.FramerateCapper(f32);
    
    return struct {
        window: sdl.video.Window = undefined,
        fps_capper: FramerateCapper = .{ 
            .mode = switch (options.frame_rate) {
                .unlimited => .unlimited,
                .limited => |fps| .{ .limited = fps },
            },
        },
        quit: bool = false,

        pub const schedules = .{
            .init = &.{
                init
            },
            .pre_update = &.{pollEvents},
            .post_render = &.{tickFramerate},
            .deinit = &.{deinit},
        };

        fn init(self: *@This(), _: *eggy.Context) !void {
            const init_flags = sdl.InitFlags{
                .video = true,
            };
            try sdl.init(init_flags);
            log.debug("SDL initialised", .{});

            try eggy.mod.rendering.ensure_renderer_is_available(backend);
            log.info("Using backend [{}]", .{backend});

            const window = try sdl.video.Window.init(options.title, options.size.x, options.size.y, .{
                .fullscreen = options.window_flags.fullscreen,
                .occluded = options.window_flags.occluded,
                .hidden = options.window_flags.hidden,
                .borderless = options.window_flags.borderless,
                .resizable = options.window_flags.resizable,
                .minimized = options.window_flags.minimized,
                .maximized = options.window_flags.maximized,
                .mouse_grabbed = options.window_flags.mouse_grabbed,
                .input_focus = options.window_flags.input_focus,
                .mouse_focus = options.window_flags.mouse_focus,
                .external = options.window_flags.external,
                .modal = options.window_flags.modal,
                .high_pixel_density = options.window_flags.high_pixel_density,
                .mouse_capture = options.window_flags.mouse_capture,
                .mouse_relative_mode = options.window_flags.mouse_relative_mode,
                .always_on_top = options.window_flags.always_on_top,
                .utility = options.window_flags.utility,
                .tooltip = options.window_flags.tooltip,
                .popup_menu = options.window_flags.popup_menu,
                .keyboard_grabbed = options.window_flags.keyboard_grabbed,
                .transparent = options.window_flags.transparent,
                .not_focusable = options.window_flags.not_focusable,
                .vulkan = true,
            });
            self.window = window;
            log.debug("Window initialised", .{});
        }

        fn deinit(this: *@This(), _: *eggy.Context) void {
            // since defer is done in reverse order, might as well add defer to make it more accurate. 
            defer sdl.quit(options.init_flags);
            defer this.window.deinit();
        }

        fn pollEvents(self: *@This(), ctx: *eggy.Context) !void {
            _ = try self.window.getSurface();
            try self.window.updateSurface();

            while (sdl.events.poll()) |event| {
                switch (event) {
                    .quit, .terminating => {
                        self.quit = true;
                        ctx.quit();
                    },
                    else => {},
                }
            }
        }

        fn tickFramerate(self: *@This(), _: *eggy.Context) void {
            _ = self.fps_capper.delay();
        }
    };
}


pub const FrameRateMode = union(enum) {
    /// No frame rate limiting
    unlimited,
    /// Limit to specific FPS
    limited: f32,
};

pub const WindowFlags = struct {
    /// Window is in fullscreen mode.
    fullscreen: bool = false,
    /// Window is occluded.
    occluded: bool = false,
    /// Window is neither mapped onto the desktop nor shown in the taskbar/dock/window list.
    /// The `video.Window.show()` function must be called for the window.
    hidden: bool = false,
    /// No window decoration.
    borderless: bool = false,
    /// Window can be resized.
    resizable: bool = false,
    /// Window is minimized.
    minimized: bool = false,
    /// Window is maximized.
    maximized: bool = false,
    /// Window has grabbed mouse input.
    mouse_grabbed: bool = false,
    /// Window has input focus.
    input_focus: bool = false,
    /// Window has mouse focus.
    mouse_focus: bool = false,
    /// Window not created by SDL.
    external: bool = false,
    /// Window is modal.
    modal: bool = false,
    /// Window uses high pixel density back buffer if possible.
    high_pixel_density: bool = false,
    /// Window has mouse captured (unrelated to `video.Window.Flags.mouse_grabbed`)
    mouse_capture: bool = false,
    /// Window has relative mode enabled.
    mouse_relative_mode: bool = false,
    /// Window should always be above others.
    always_on_top: bool = false,
    /// Window should be treated as a utility window, not showing in the task bar and window list.
    utility: bool = false,
    /// Window should be treated as a tooltip and does not get mouse or keyboard focus, requires a parent window.
    tooltip: bool = false,
    /// Window should be treated as a popup menu, requires a parent window.
    popup_menu: bool = false,
    /// Window has grabbed keyboard input.
    keyboard_grabbed: bool = false,
    /// Window is in fill-document mode (Emscripten only), since SDL 3.4.0.
    fill_document: bool = false,
    /// Window with transparent buffer.
    transparent: bool = false,
    /// Window should not be focusable.
    not_focusable: bool = false,
};
