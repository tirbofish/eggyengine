const std = @import("std");
const ecs = @import("eggyecs/ecs.zig");

pub const Context = struct {
    world: *ecs.World,
    allocator: std.mem.Allocator,
    delta_time: f32,
    running: *bool,
    
    pub fn spawn(self: *Context, components: anytype) ecs.Entity {
        return self.world.spawn(components);
    }
    
    pub fn despawn(self: *Context, entity: ecs.Entity) void {
        self.world.despawn(entity);
    }
    
    pub fn query(self: *Context, comptime Components: type) ecs.QueryIter(Components) {
        return self.world.query(Components);
    }
    
    pub fn quit(self: *Context) void {
        self.running.* = false;
    }
};