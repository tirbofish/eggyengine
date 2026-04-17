const std = @import("std");
const ecs = @import("ecs.zig");
const eggy = @import("eggy.zig");

pub const Context = struct {
    world: *ecs.World,
    allocator: std.mem.Allocator,
    delta_time: f32,
    running: *bool,

    pub fn quit(self: *Context) void {
        eggy.logger.debug("Quit signal received from eggy.Context", @src()) catch {};
        self.running.* = false;
    }
};
