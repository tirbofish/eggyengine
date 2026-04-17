const std = @import("std");
const eggy = @import("eggy");

pub fn main() !void {
    var app = try eggy.EggyApp(&.{
        eggy.module.DefaultModule(.{}, eggy.module.rendering.vulkan.EggyVulkanInterface(.{})),
        struct {
            pub const schedules = .{ .update = &.{escape_to_quit} };
        },
    }).init(std.heap.page_allocator, .{});
    defer app.deinit();

    app.run();
}

fn escape_to_quit(ctx: *eggy.Context) !void {
    if (ctx.world.getResource(eggy.module.input.KeyboardInput)) |key| {
        if (key.isPressed(.escape)) {
            ctx.quit();
        }
    }
}
