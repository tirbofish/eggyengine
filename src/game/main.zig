const std = @import("std");
const eggy = @import("eggy");

const pipeline = eggy.module.rendering.vulkan.pipeline;
const cmd = eggy.module.rendering.vulkan.cmd;

pub fn main() !void {
    var app = try eggy.EggyApp(&.{ eggy.module.DefaultModule(.{}, eggy.module.rendering.vulkan.EggyVulkanInterface), struct {
        pub const schedules = .{ .update = &.{escape_to_quit} };
    }, VKModule }).init(std.heap.page_allocator, .{});
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

pub const VKModule = struct {
    pipeline: pipeline.Pipeline = undefined,

    pub const schedules = .{
        .init = .{init},
        .render = .{render},
        .deinit = .{deinit},
    };

    pub fn init(self: *@This(), ctx: *eggy.Context) !void {
        const vulkan = ctx.world.getResource(eggy.module.rendering.vulkan.EggyVulkanInterface) orelse return;

        const shader_file = try std.fs.cwd().openFile("zig-out/bin/shaders/shader.spv", .{});
        defer shader_file.close();

        var shader = try pipeline.Shader.init_from_file(vulkan, shader_file, ctx.allocator);
        defer shader.deinit();

        var builder = pipeline.Pipeline.builder(vulkan);
        self.pipeline = try builder
            .vertexShader(shader.module, "vertMain")
            .fragmentShader(shader.module, "fragMain")
            .topology(.triangle_list)
            .cullMode(.back)
            .frontFace(.clockwise)
            .polygonMode(.fill)
            .build();
    }

    pub fn render(self: *@This(), ctx: *eggy.Context) !void {
        const vulkan = ctx.world.getResource(eggy.module.rendering.vulkan.EggyVulkanInterface) orelse return;

        var frame = cmd.Frame.acquire(vulkan) catch |err| switch (err) {
            error.SurfaceLost => {
                std.debug.print("Frame.acquire failed: SurfaceLost\n", .{});
                ctx.quit();
                return;
            },
            error.SwapchainOutOfDate => {
                std.debug.print("Frame.acquire failed: SwapchainOutOfDate\n", .{});
                // TODO: recreate swapchain
                return;
            },
            else => {
                std.debug.print("Frame.acquire failed: {any}\n", .{err});
                return err;
            },
        };

        frame.beginRendering(.cornflower_blue);
        frame.bindPipeline(self.pipeline);
        frame.draw(3, 1, 0, 0);
        frame.endRendering();

        try frame.submit();
    }

    pub fn deinit(self: *@This(), _: *eggy.Context) void {
        self.pipeline.deinit();
    }
};