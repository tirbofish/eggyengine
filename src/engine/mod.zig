const std = @import("std");
const eggy = @import("eggy.zig");

/// This module allows for you to run a simple window and a renderer, as well as input and more. 
/// 
/// # Backends
/// ## Graphics
pub const DefaultModule = struct {
    pub const schedules = .{
        .startup = &.{init}
    };
};

fn init(_: *eggy.Context) void {
    
}