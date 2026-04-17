const sdl = @import("sdl3");
const std = @import("std");
const eggy = @import("eggy.zig");

pub const vulkan = @import("rendering/vulkan.zig");

pub const SdlBackend = enum {
    vulkan,
    opengl,
};

pub fn RenderingModule(comptime BackendImpl: type) type {
    return struct {
        rendering_interface: ?Renderer = null,

        pub const sdl_backend: SdlBackend = if (@hasDecl(BackendImpl, "sdl_backend"))
            BackendImpl.sdl_backend
        else
            @compileError("Backend '" ++ @typeName(BackendImpl) ++ "' must declare 'pub const sdl_backend: rendering.SdlBackend'");

        pub const schedules = .{
            .init = &.{init},
            .deinit = &.{deinit},
        };

        fn init(self: *@This(), ctx: *eggy.Context) !void {
            if (@hasDecl(BackendImpl, "ensure_available")) {
                try BackendImpl.ensure_available();
            }

            const backend_name = if (@hasDecl(BackendImpl, "name")) BackendImpl.name else @typeName(BackendImpl);
            std.log.info("Using backend [{s}]", .{backend_name});

            const window = ctx.world.getResource(sdl.video.Window) orelse return error.WindowNotFound;
            const impl = try ctx.allocator.create(BackendImpl);
            impl.* = try BackendImpl.init(ctx.allocator, window.*);
            self.rendering_interface = Renderer.init(impl, ctx.allocator);
        }

        fn deinit(self: *@This(), _: *eggy.Context) void {
            if (self.rendering_interface) |ri| {
                ri.deinit();
            }
        }
    };
}

pub const Renderer = struct {
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    deinitFn: *const fn (*anyopaque) void,
    destroyFn: *const fn (std.mem.Allocator, *anyopaque) void,

    pub fn init(ptr: anytype, allocator: std.mem.Allocator) Renderer {
        const Ptr = @TypeOf(ptr);
        return .{
            .ptr = @ptrCast(ptr),
            .allocator = allocator,
            .deinitFn = struct {
                fn thunk(p: *anyopaque) void {
                    const self: Ptr = @ptrCast(@alignCast(p));
                    self.deinit();
                }
            }.thunk,
            .destroyFn = struct {
                fn destroy(alloc: std.mem.Allocator, p: *anyopaque) void {
                    alloc.destroy(@as(Ptr, @ptrCast(@alignCast(p))));
                }
            }.destroy,
        };
    }

    pub fn deinit(self: Renderer) void {
        self.deinitFn(self.ptr);
        self.destroyFn(self.allocator, self.ptr);
    }
};