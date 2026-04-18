const std = @import("std");
const eggy = @import("eggy.zig");
const vk = @import("vulkan");

pub const windowing = @import("windowing.zig");
pub const rendering = @import("rendering.zig");
pub const input = @import("input.zig");

pub const DefaultModuleOptions = struct {
    windowing_options: windowing.WindowingModuleOptions = .{},
};

/// This module allows for you to run a simple window and a renderer, as well as input and more.
///
/// # Backends
/// ## Windowing
/// - SDL3
/// ## Graphics
/// - vulkan - Options can be provided through [`eggy.mod.rendering.vulkan.EggyVulkanInterface`]
///
/// # Example
/// ```zig
/// eggy.mod.DefaultModule(.{}, eggy.module.rendering.vulkan.EggyVulkanInterface(.{}))
/// ```
pub fn DefaultModule(comptime options: DefaultModuleOptions, comptime BackendImpl: type) type {
    return struct {
        pub const sub_modules = &.{
            // order matters, dont change its existing order.
            input.InputModule(),
            windowing.WindowingModule(options.windowing_options, BackendImpl.sdl_backend),
            rendering.RenderingModule(BackendImpl),
        };

        pub const schedules = .{
            .init = .{init},
        };

        pub fn init(ctx: *eggy.Context) !void {
            const vulkan = ctx.world.getResource(rendering.vulkan.EggyVulkanInterface) orelse return;

            const shader_file = try std.fs.cwd().openFile("zig-out/shaders/shader.spv", .{});
            const stat = try shader_file.stat();
            const contents = try shader_file.readToEndAlloc(ctx.allocator, stat.size);
            var shader = try rendering.vulkan.pipeline.Shader.init(vulkan, contents);
            defer shader.deinit();

            const vert = vk.PipelineShaderStageCreateInfo{
                .module = shader.module,
                .stage = .{ .vertex_bit = true },
                .p_name = "vertMain",
            };

            const frag = vk.PipelineShaderStageCreateInfo{
                .module = shader.module,
                .stage = .{ .fragment_bit = true },
                .p_name = "fragMain",
            };

            const visci = vk.PipelineVertexInputStateCreateInfo{
                .vertex_binding_description_count = 0,
                .p_vertex_binding_descriptions = null,
                .vertex_attribute_description_count = 0,
                .p_vertex_attribute_descriptions = null,
            };

            const iasci = vk.PipelineInputAssemblyStateCreateInfo{
                .topology = .triangle_list,
                .primitive_restart_enable = .false,
            };

            const viewport_state = vk.PipelineViewportStateCreateInfo{
                .viewport_count = 1,
                .scissor_count = 1,
            };

            const rasteriser = vk.PipelineRasterizationStateCreateInfo{
                .depth_clamp_enable = .false,
                .rasterizer_discard_enable = .false,
                .polygon_mode = .fill,
                .cull_mode = .{ .back_bit = true },
                .front_face = .clockwise,
                .depth_bias_enable = .false,
                .depth_bias_constant_factor = 0.0,
                .depth_bias_clamp = 0.0,
                .depth_bias_slope_factor = 0.0,
                .line_width = 1.0,
            };

            const multisampling = vk.PipelineMultisampleStateCreateInfo{
                .rasterization_samples = .{ .@"1_bit" = true },
                .sample_shading_enable = .false,
                .min_sample_shading = 1.0,
                .alpha_to_coverage_enable = .false,
                .alpha_to_one_enable = .false,
            };

            const colour_blend_attachment = vk.PipelineColorBlendAttachmentState{
                .blend_enable = .false,
                .src_color_blend_factor = .one,
                .dst_color_blend_factor = .zero,
                .color_blend_op = .add,
                .src_alpha_blend_factor = .one,
                .dst_alpha_blend_factor = .zero,
                .alpha_blend_op = .add,
                .color_write_mask = .{ .r_bit = true, .b_bit = true, .g_bit = true, .a_bit = true },
            };

            const colour_blending = vk.PipelineColorBlendStateCreateInfo{
                .logic_op_enable = .false,
                .logic_op = .copy,
                .attachment_count = 1,
                .p_attachments = @ptrCast(&colour_blend_attachment),
                .blend_constants = .{ 0.0, 0.0, 0.0, 0.0 },
            };

            const dynamic_states = [_]vk.DynamicState{ .viewport, .scissor };

            const dynamic_state_info = vk.PipelineDynamicStateCreateInfo{
                .dynamic_state_count = dynamic_states.len,
                .p_dynamic_states = &dynamic_states,
            };

            const p_create_info = vk.PipelineLayoutCreateInfo{
                .set_layout_count = 0,
                .push_constant_range_count = 0,
            };
            const pipeline_layout = try vulkan.device.createPipelineLayout(&p_create_info, null);

            const rendering_info = vk.PipelineRenderingCreateInfo{
                .color_attachment_count = 1,
                .p_color_attachment_formats = &[_]vk.Format{vulkan.swapchain.surface_format.format},
                .depth_attachment_format = .undefined,
                .stencil_attachment_format = .undefined,
                .view_mask = 0,
            };

            const gpci = vk.GraphicsPipelineCreateInfo{ .stage_count = 2, .p_stages = @ptrCast(&[_]vk.PipelineShaderStageCreateInfo{ vert, frag }), .p_vertex_input_state = &visci, .p_input_assembly_state = &iasci, .p_viewport_state = &viewport_state, .p_rasterization_state = &rasteriser, .p_multisample_state = &multisampling, .p_color_blend_state = &colour_blending, .p_dynamic_state = &dynamic_state_info, .layout = pipeline_layout, .render_pass = .null_handle, .subpass = 0, .base_pipeline_handle = .null_handle, .base_pipeline_index = -1, .p_next = @ptrCast(&rendering_info) };

            var pipeline: vk.Pipeline = undefined;
            _ = try vulkan.device.createGraphicsPipelines(
                .null_handle,
                1,
                @ptrCast(&gpci),
                null,
                @ptrCast(&pipeline),
            );
        }
    };
}
