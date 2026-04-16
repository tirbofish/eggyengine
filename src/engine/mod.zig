const std = @import("std");
const eggy = @import("eggy.zig");
pub const windowing = @import("windowing.zig");
pub const rendering = @import("rendering.zig");

pub const DefaultModuleOptions = struct {
    windowing_options: windowing.WindowingModuleOptions = .{},
    backend: rendering.Backend = rendering.Backend.Vulkan,
};

/// This module allows for you to run a simple window and a renderer, as well as input and more. 
/// 
/// # Backends
/// ## Windowing
/// - SDL3
/// ## Graphics
/// - vulkan
pub fn DefaultModule(comptime options: DefaultModuleOptions) type {
    return struct {
        pub const sub_modules = &.{
            windowing.WindowingModule(options.windowing_options, options.backend),
            rendering.RenderingModule(options.backend)
        };

        pub const schedules = .{};
    };
}