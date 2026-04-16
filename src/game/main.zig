const std = @import("std");
const eggy = @import("eggy");

pub fn main() !void {
    var app = eggy.EggyApp(&.{
        
    }).init(std.heap.page_allocator);
    defer app.deinit();
    
    app.run();
}

const Position = struct { x: f32, y: f32 };
const Velocity = struct { dx: f32, dy: f32 };
const Health = struct { current: i32, max: i32 };

const TestingModule = struct {
    counter: u32 = 0,
    
    pub const schedules = .{
        .startup = &.{spawn},
        .update = &.{ movement },
        .render = &.{draw},
        .shutdown = &.{shutdown},
    };

    fn spawn(_: *@This(), ctx: *eggy.Context) void {
        _ = ctx.world.spawn(.{
            Position{ .x = 0, .y = 0 },
            Velocity{ .dx = 100, .dy = 50 },
            Health{ .current = 100, .max = 100 },
        }) catch return;
    
        _ = ctx.world.spawn(.{
            Position{ .x = 10, .y = 10 },
            Velocity{ .dx = 200, .dy = 0 },
        }) catch return;
    }
    
    fn movement(_: *@This(), ctx: *eggy.Context) void {
        var q = ctx.world.query_mut(struct { 
            pos: Position, 
            vel: Velocity 
        });
        while (q.next()) |result| {
            result.components.pos.x += result.components.vel.dx * ctx.delta_time;
            result.components.pos.y += result.components.vel.dy * ctx.delta_time;
            
            std.debug.print("Entity {} at ({d:.2}, {d:.2})\n", .{
                result.entity.id,
                result.components.pos.x,
                result.components.pos.y,
            });
        }
    }
    
    fn draw(_: *@This(), ctx: *eggy.Context) void {
        std.log.info("fps: {d}", .{1/ctx.delta_time});
    }

    fn shutdown(_: *@This(), _: *eggy.Context) void {
        std.log.info("Shutting down", .{});
    }
};