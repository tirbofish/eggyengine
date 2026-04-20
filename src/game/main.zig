const std = @import("std");
const eggy = @import("eggy");

const rendering = eggy.module.rendering.vulkan;
const pipeline = rendering.pipeline;
const cmd = rendering.cmd;

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

pub const Vertex = struct {
    position: eggy.math.Vec2,
    colour: eggy.colour.Colour,

    pub fn getBindingDescription() pipeline.VertexBinding {
        return .{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .input_rate = .vertex,
        };
    }

    pub fn getAttributeDescriptions() [2]pipeline.VertexAttribute {
        return .{
            .{
                .location = 0,
                .binding = 0,
                .format = .float2,
                .offset = @offsetOf(Vertex, "position"),
            },
            .{
                .location = 1,
                .binding = 0,
                .format = .float3,
                .offset = @offsetOf(Vertex, "colour"),
            },
        };
    }
};

pub const VKModule = struct {
    const vertices = [_]Vertex {
        .{
            .position = eggy.math.Vec2.init(-0.5, -0.5),
            .colour = eggy.colour.Colour.from_f32(1.0, 0.0, 0.0)
        },
        .{
            .position = eggy.math.Vec2.init(0.5, -0.5),
            .colour = eggy.colour.Colour.from_f32(0.0, 1.0, 0.0)
        },
        .{
            .position = eggy.math.Vec2.init(0.5, 0.5),
            .colour = eggy.colour.Colour.from_f32(0.0, 0.0, 1.0)
        },
        .{
            .position = eggy.math.Vec2.init(-0.5, 0.5),
            .colour = eggy.colour.Colour.from_f32(1.0, 1.0, 1.0)
        },
    };
    const indices = [_]u16 {
        0, 1, 2,
        2, 3, 0
    };
    
    pipeline: pipeline.Pipeline = undefined,

    vertex_buffer: rendering.buffer.VertexBuffer(Vertex) = undefined,
    index_buffer: rendering.buffer.IndexBuffer(u16) = undefined,

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

        var builder = pipeline.Pipeline.builder(vulkan, ctx.allocator);
        defer builder.deinit();
        self.pipeline = try builder
            .vertexShader(shader.module, "vertMain")
            .fragmentShader(shader.module, "fragMain")
            .topology(.triangle_list)
            .cullMode(.back)
            .frontFace(.clockwise)
            .polygonMode(.fill)
            .addVertexBinding(Vertex.getBindingDescription())
            .addVertexAttributes(&Vertex.getAttributeDescriptions())
            .build();
        
        self.vertex_buffer = try rendering.buffer.VertexBuffer(Vertex).init(vulkan, &vertices);
        self.index_buffer = try rendering.buffer.IndexBuffer(u16).init(vulkan, &indices);
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
                try vulkan.swapchain.recreate(vulkan);
                return;
            },
            else => {
                std.debug.print("Frame.acquire failed: {any}\n", .{err});
                return err;
            },
        };

        {
            var pass = frame.beginRenderPass(.{
                .color_attachment = .{
                    .clear_color = eggy.colour.Colour.transparent,
                    .load_op = .clear,
                    .store_op = .store,
                },
            });
            defer pass.end();

            pass.setPipeline(self.pipeline);
            pass.setVertexBuffer(self.vertex_buffer);
            pass.setIndexBuffer(self.index_buffer, .uint16);
            pass.drawIndexed(indices.len, 1, 0, 0, 0);
        }

        const submit_result = try frame.submit();
        if (submit_result == .swapchain_out_of_date or submit_result == .swapchain_suboptimal) {
            try vulkan.swapchain.recreate(vulkan);
        }
    }

    pub fn deinit(self: *@This(), _: *eggy.Context) void {
        self.vertex_buffer.deinit();
        self.index_buffer.deinit();
        self.pipeline.deinit();
    }
};