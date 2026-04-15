const std = @import("std");
const eggy = @import("eggy");

pub fn main() !void {
    const App = eggy.EggyApp(&.{TestingModule});

    var app = App.init(std.heap.page_allocator);
    defer app.deinit();
    
    app.run();
}

const TestingModule = struct {
    counter: u32 = 0,
    
    pub const schedules = .{
        .startup = &.{spawn},
        .update = &.{ movement, combat },
        .render = &.{draw},
        .shutdown = &.{shutdown},
    };

    fn spawn(self: *@This(), ctx: *eggy.context.Context) void {
        _ = self;
        _ = ctx.spawn(.{}); // spawn a player entity
        std.log.info("Player spawned!", .{});
    }
    
    fn movement(self: *@This(), ctx: *eggy.context.Context) void {
        self.counter += 1;
        _ = ctx;
    }
    
    fn combat(_: *@This(), _: *eggy.context.Context) void {
    }
    
    fn draw(_: *@This(), ctx: *eggy.context.Context) void {
        std.log.info("fps: {d}", .{ctx.delta_time});
    }

    fn shutdown(_: *@This(), _: *eggy.context.Context) void {
        std.log.info("Shutting down", .{});
    }
};