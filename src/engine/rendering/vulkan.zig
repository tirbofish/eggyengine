const sdl = @import("sdl3");
const vk = @import("vulkan");
const builtin = @import("builtin");
const std = @import("std");
const rendering = @import("../rendering.zig");

const Allocator = std.mem.Allocator;
const SdlBackend = rendering.SdlBackend;

/// Options for a Vulkan renderer
pub const Options = struct {
    app_name: [*:0]const u8 = "eggyengine app",
    engine_name: [*:0]const u8 = "eggyengine",
    app_version: u32 = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
    engine_version: u32 = @bitCast(vk.makeApiVersion(0, 1, 0, 0)),
    api_version: u32 = @bitCast(vk.API_VERSION_1_4),
    enable_validation_layers: bool = @import("builtin").mode == .Debug,
    extra_layers: []const [*:0]const u8 = &.{},
    extra_extensions: []const [*:0]const u8 = &.{},
};

/// Inherits `BackendImpl`
pub fn EggyVulkanInterface(comptime options: Options) type {
    const validation_layer_names = if (options.enable_validation_layers)
        [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"}
    else
        [_][*:0]const u8{};

    return struct {
        pub const sdl_backend: SdlBackend = .vulkan;
        pub const name = "Vulkan";

        pub fn ensure_available() !void {
            try sdl.vulkan.loadLibrary(null);
            std.log.debug("Vulkan library is loaded", .{});
        }
        allocator: Allocator,
        vkb: vk.BaseWrapper,
        instance: vk.InstanceProxy,
        surface: vk.SurfaceKHR,
        sdl_surface: sdl.vulkan.Surface,

        pub fn init(allocator: Allocator, window: sdl.video.Window) !@This() {
            var self: @This() = undefined;
            self.allocator = allocator;

            const get_proc_addr = try sdl.vulkan.getVkGetInstanceProcAddr();
            self.vkb = vk.BaseWrapper.load(@as(vk.PfnGetInstanceProcAddr, @ptrCast(get_proc_addr)));

            if (options.enable_validation_layers) {
                if (try checkLayerSupport(&self.vkb, allocator, &validation_layer_names) == false) {
                    return error.MissingValidationLayer;
                }
            }

            const sdl_extensions = try sdl.vulkan.getInstanceExtensions();

            var extensions: std.ArrayList([*:0]const u8) = .empty;
            defer extensions.deinit(allocator);

            try extensions.appendSlice(allocator, sdl_extensions);

            if (options.enable_validation_layers) {
                try extensions.append(allocator, vk.extensions.ext_debug_utils.name);
            }

            for (options.extra_extensions) |ext| {
                try extensions.append(allocator, ext);
            }

            var layers: std.ArrayList([*:0]const u8) = .empty;
            defer layers.deinit(allocator);

            try layers.appendSlice(allocator, &validation_layer_names);
            for (options.extra_layers) |layer| {
                try layers.append(allocator, layer);
            }

            const instance_handle = try self.vkb.createInstance(&.{
                .p_application_info = &.{
                    .p_application_name = options.app_name,
                    .application_version = @bitCast(options.app_version),
                    .p_engine_name = options.engine_name,
                    .engine_version = @bitCast(options.engine_version),
                    .api_version = @bitCast(options.api_version),
                },
                .enabled_layer_count = @intCast(layers.items.len),
                .pp_enabled_layer_names = @ptrCast(layers.items.ptr),
                .enabled_extension_count = @intCast(extensions.items.len),
                .pp_enabled_extension_names = @ptrCast(extensions.items.ptr),
            }, null);

            const vki = try allocator.create(vk.InstanceWrapper);
            errdefer allocator.destroy(vki);
            vki.* = vk.InstanceWrapper.load(instance_handle, self.vkb.dispatch.vkGetInstanceProcAddr.?);
            self.instance = vk.InstanceProxy.init(instance_handle, vki);
            std.log.debug("Initialised vk.Instance", .{});
            errdefer self.instance.destroyInstance(null);

            const surface_result = try createSurface(self.instance, window);
            std.log.debug("Initialised vk.Surface", .{});
            self.surface = surface_result.vk_surface;
            self.sdl_surface = surface_result.sdl_surface;

            return self;
        }

        pub fn deinit(self: *@This()) void {
            self.sdl_surface.deinit();
            self.instance.destroyInstance(null);
            self.allocator.destroy(self.instance.wrapper);
        }
    };
}

const SurfaceResult = struct {
    vk_surface: vk.SurfaceKHR,
    sdl_surface: sdl.vulkan.Surface,
};

fn createSurface(instance: vk.InstanceProxy, window: sdl.video.Window) !SurfaceResult {
    const sdl_instance: sdl.vulkan.Instance = @ptrFromInt(@intFromEnum(instance.handle));
    const sdl_surface = try sdl.vulkan.Surface.init(window, sdl_instance, null);
    return .{
        .vk_surface = @enumFromInt(@intFromPtr(sdl_surface.surface)),
        .sdl_surface = sdl_surface,
    };
}

fn checkLayerSupport(vkb: *const vk.BaseWrapper, alloc: Allocator, required_layers: []const [*:0]const u8) !bool {
    const available_layers = try vkb.enumerateInstanceLayerPropertiesAlloc(alloc);
    defer alloc.free(available_layers);
    for (required_layers) |required_layer| {
        for (available_layers) |layer| {
            if (std.mem.eql(u8, std.mem.span(required_layer), std.mem.sliceTo(&layer.layer_name, 0))) {
                break;
            }
        } else {
            return false;
        }
    }
    return true;
}