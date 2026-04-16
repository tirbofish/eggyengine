const std = @import("std");
const eggy = @import("eggy.zig");
const windowing = @import("windowing.zig");

pub const DefaultModuleOptions = struct {
    windowing_options: windowing.WindowingModuleOptions = .{},
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
            windowing.WindowingModule(options.windowing_options)
        };

        pub const schedules = .{
            .startup = &.{init}
        };
    };
}

fn init(_: *eggy.Context) void {
    
}