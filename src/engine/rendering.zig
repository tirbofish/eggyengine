const sdl = @import("sdl3");
const std = @import("std");
const eggy = @import("eggy.zig");

pub const vulkan = @import("rendering/vulkan.zig");

pub const Backend = enum {
    /// Enables rendering using the Vulkan backend. 
    Vulkan,
};

pub fn ensure_renderer_is_available(backend: Backend) !void {
    switch (backend) {
        Backend.Vulkan => {
            try sdl.vulkan.loadLibrary(null);
            std.log.debug("Vulkan library is loaded", .{});
        }
    }
}

pub fn RenderingModule(backend: Backend) type {
    return struct {
        pub const schedules = .{
            .init = &.{init},
        };

        fn init(_: *eggy.Context) !void {
            switch (backend) {
                Backend.Vulkan => {
                    
                }
            }
        }
    };
}