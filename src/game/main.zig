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
    
    fn combat(self: *@This(), ctx: *eggy.context.Context) void {
        _ = self;
        _ = ctx;
    }
    
    fn draw(self: *@This(), ctx: *eggy.context.Context) void {
        _ = ctx;
        std.log.info("counter: {d}", .{self.counter});
    }
};