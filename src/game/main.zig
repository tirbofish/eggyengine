const std = @import("std");
const eggy = @import("eggy");

const rendering = eggy.module.rendering.vulkan;
const pipeline = rendering.pipeline;
const cmd = rendering.cmd;
const vk = rendering.vk;

const file = @embedFile("image.png");

pub fn main(init: std.process.Init) !void {
    var app = try eggy.EggyApp(&.{ eggy.module.DefaultModule(.{}, eggy.module.rendering.vulkan.EggyVulkanInterface), struct {
        pub const schedules = .{ .update = &.{escape_to_quit} };
    }, VKModule }).init(init, .{});
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

pub const UBO = struct {
    model: eggy.math.Mat4 = eggy.math.identity(f32, 4),
    view: eggy.math.Mat4 = eggy.math.identity(f32, 4),
    proj: eggy.math.Mat4 = eggy.math.identity(f32, 4),
};

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
    start_time: i128 = 0,

    vertex_buffer: rendering.buffer.VertexBuffer(Vertex) = undefined,
    index_buffer: rendering.buffer.IndexBuffer(u16) = undefined,
    uniform_buffer: rendering.buffer.UniformBuffer(UBO) = undefined,

    ubo: UBO = undefined,
    image: rendering.texture.Texture = undefined,

    pub const schedules = .{
        .init = .{init},
        .update = .{update},
        .pre_render = .{pre_render},
        .render = .{render},
        .post_render = .{post_render},
        .deinit = .{deinit},
    };

    pub fn init(self: *@This(), ctx: *eggy.Context) !void {
        const vulkan = ctx.world.getResource(eggy.module.rendering.vulkan.EggyVulkanInterface) orelse return;

        const shader_file = try std.Io.Dir.cwd().openFile(ctx.proc_init.io, "zig-out/bin/shaders/shader.spv", .{});
        defer shader_file.close(ctx.proc_init.io);

        var shader = try pipeline.Shader.init_from_file(vulkan, shader_file, ctx);
        defer shader.deinit();

        var builder = pipeline.Pipeline.builder(vulkan, ctx.allocator, "main pipeline");
        defer builder.deinit();
        self.pipeline = try builder
            .vertexShader(shader.module, "vertMain")
            .fragmentShader(shader.module, "fragMain")
            .addDescriptorBinding(.uniformBuffer(0, .{ .vertex = true }))
            .topology(.triangle_list)
            .cullMode(.back)
            .frontFace(.counter_clockwise)
            .polygonMode(.fill)
            .addVertexBinding(Vertex.getBindingDescription())
            .addVertexAttributes(&Vertex.getAttributeDescriptions())
            .build();
        
        self.vertex_buffer = try rendering.buffer.VertexBuffer(Vertex).init(vulkan, &vertices, "quad vertex buffer");
        self.index_buffer = try rendering.buffer.IndexBuffer(u16).init(vulkan, &indices, "quad index buffer");

        self.uniform_buffer = try rendering.buffer.UniformBuffer(UBO).init(vulkan, self.pipeline, "uniform buffer");
        self.image = try rendering.texture.Texture.initFromMemory(ctx, vulkan, file, "flight image");
        self.start_time = @intCast(std.Io.Clock.now(.awake, ctx.proc_init.io).nanoseconds);
    }

    pub fn update(self: *@This(), ctx: *eggy.Context) !void {
        const vulkan = ctx.world.getResource(eggy.module.rendering.vulkan.EggyVulkanInterface) orelse return;
        const currentTime: i128 = @intCast(std.Io.Clock.now(.awake, ctx.proc_init.io).nanoseconds);
        
        const time: f32 = @as(f32, @floatFromInt(currentTime - self.start_time)) / 1_000_000_000.0;

        self.ubo.model = eggy.math.Quat.identity().rotate(time * std.math.degreesToRadians(90.0), eggy.math.Vec3.unit_z).toMatrix();
        self.ubo.view = eggy.math.lookAt(
            eggy.math.Vec3.init(2.0, 2.0, 2.0),
            eggy.math.Vec3.zero,
            eggy.math.Vec3.unit_z
        );
        const aspect: f32 = @as(f32, @floatFromInt(vulkan.swapchain.swapchain_extent.width)) / 
                            @as(f32, @floatFromInt(vulkan.swapchain.swapchain_extent.height));
        self.ubo.proj = eggy.math.perspective(
            std.math.degreesToRadians(45.0), 
            aspect,
            0.1,
            10.0
        );

        self.uniform_buffer.write(self.ubo);
    }

    pub fn pre_render(ctx: *eggy.Context) !void {
        const vulkan = ctx.world.getResource(eggy.module.rendering.vulkan.EggyVulkanInterface) orelse return;

        vulkan.beginFrame("command buffer") catch |err| switch (err) {
            error.SurfaceLost => {
                std.debug.print("beginFrame failed: SurfaceLost\n", .{});
                ctx.quit();
                return;
            },
            error.SwapchainOutOfDate => {
                std.debug.print("beginFrame failed: SwapchainOutOfDate\n", .{});
                try vulkan.swapchain.recreate(vulkan);
                return;
            },
            else => {
                std.debug.print("beginFrame failed: {any}\n", .{err});
                return err;
            },
        };
    }

    pub fn render(self: *@This(), ctx: *eggy.Context) !void {
        const vulkan = ctx.world.getResource(eggy.module.rendering.vulkan.EggyVulkanInterface) orelse return;
        var command_buffer = cmd.CommandBuffer.init(vulkan);

        command_buffer.beginRendering(.{
            .color_attachment = .{
                .clear_color = eggy.colour.Colour.transparent,
                .load_op = .clear,
                .store_op = .store,
            },
        });

        command_buffer.bindPipeline(self.pipeline);
        command_buffer.bindVertexBuffer(self.vertex_buffer);
        command_buffer.bindIndexBuffer(self.index_buffer, .uint16);
        command_buffer.bindDescriptor(self.uniform_buffer, self.pipeline);
        command_buffer.drawIndexed(indices.len, 1, 0, 0, 0);

        command_buffer.endRendering();
    }

    pub fn post_render(ctx: *eggy.Context) !void {
        const vulkan = ctx.world.getResource(eggy.module.rendering.vulkan.EggyVulkanInterface) orelse return;
        var command_buffer = cmd.CommandBuffer.init(vulkan);

        const submit_result = try vulkan.endFrame(&command_buffer);
        if (submit_result == .swapchain_out_of_date or submit_result == .swapchain_suboptimal) {
            try vulkan.swapchain.recreate(vulkan);
        }
    }

    pub fn deinit(self: *@This(), _: *eggy.Context) void {
        self.image.deinit();
        self.vertex_buffer.deinit();
        self.index_buffer.deinit();
        self.uniform_buffer.deinit();
        self.pipeline.deinit();
    }
};