const std = @import("std");
const eggy = @import("eggy");

pub fn main() !void {
    var app = eggy.EggyApp(&.{
        eggy.mod.DefaultModule(
            .{},
            eggy.mod.rendering.vulkan.EggyVulkanInterface(.{})
        )
    }).init(std.heap.page_allocator, .{});
    defer app.deinit();
    
    app.run();
}