const std = @import("std");
const ecs = @import("eggyecs/ecs.zig");

pub const Context = struct {
    world: *ecs.World,
    allocator: std.mem.Allocator,
    delta_time: f32,
    running: *bool,
    
    pub fn quit(self: *Context) void {
        self.running.* = false;
    }
};