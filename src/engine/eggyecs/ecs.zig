const std = @import("std");
const context = @import("../ctx.zig");

pub const Schedule = enum {
    startup,
    update,
    fixed_update,
    render,
    shutdown,
};

pub const Entity = struct {
    id: u64,
    generation: u16,
    
    pub fn despawn(self: Entity, ctx: *context.Context) void {
        ctx.world.despawn(self);
    }
};

pub const World = struct {
    allocator: std.mem.Allocator,
    next_entity_id: u64 = 0,
    
    pub fn init(allocator: std.mem.Allocator) World {
        return .{ .allocator = allocator };
    }
    
    pub fn deinit(self: *World) void {
        _ = self;
    }
    
    pub fn spawn(self: *World, components: anytype) Entity {
        const id = self.next_entity_id;
        self.next_entity_id += 1;
        _ = components;
        return .{ .id = id, .generation = 0 };
    }
    
    pub fn despawn(self: *World, entity: Entity) void {
        _ = self;
        _ = entity;
    }
    
    pub fn query(self: *World, comptime Components: type) QueryIter(Components) {
        return QueryIter(Components).init(self);
    }
};

pub fn QueryIter(comptime Components: type) type {
    return struct {
        world: *World,
        index: usize = 0,
        
        pub fn init(world: *World) @This() {
            return .{ .world = world };
        }
        
        pub fn next(self: *@This()) ?Components {
            _ = self;
            return null;
        }
    };
}