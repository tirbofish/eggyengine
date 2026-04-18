const rendering = @import("vulkan.zig");
const vk = @import("vulkan");
const std = @import("std");

pub const Shader = struct {
    e_vulkan: *rendering.EggyVulkanInterface,
    module: vk.ShaderModule,

    /// Helper function to create a shader module from SPIR-V contents.
    pub fn init_from_file(e_vulkan: *rendering.EggyVulkanInterface, file: std.fs.File, allocator: std.mem.Allocator) !@This() {
        const stat = try file.stat();
        const contents = try file.readToEndAlloc(allocator, stat.size);
        defer allocator.free(contents);

        return try Shader.init(e_vulkan, contents);
    }

    /// Create a shader module from SPIR-V contents.
    pub fn init(e_vulkan: *rendering.EggyVulkanInterface, spirv_contents: []const u8) !@This() {
        const shader_create_info: vk.ShaderModuleCreateInfo = .{
            .code_size = spirv_contents.len,
            .p_code = @ptrCast(@alignCast(spirv_contents.ptr)),
        };

        const module = try e_vulkan.device.createShaderModule(
            &shader_create_info,
            null,
        );

        return .{
            .e_vulkan = e_vulkan,
            .module = module,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.e_vulkan.device.destroyShaderModule(self.module, null);
    }
};

pub const Topology = enum {
    point_list,
    line_list,
    line_strip,
    triangle_list,
    triangle_strip,
    triangle_fan,

    fn toVk(self: Topology) vk.PrimitiveTopology {
        return switch (self) {
            .point_list => .point_list,
            .line_list => .line_list,
            .line_strip => .line_strip,
            .triangle_list => .triangle_list,
            .triangle_strip => .triangle_strip,
            .triangle_fan => .triangle_fan,
        };
    }
};

pub const CullMode = enum {
    none,
    front,
    back,
    front_and_back,

    fn toVk(self: CullMode) vk.CullModeFlags {
        return switch (self) {
            .none => .{},
            .front => .{ .front_bit = true },
            .back => .{ .back_bit = true },
            .front_and_back => .{ .front_bit = true, .back_bit = true },
        };
    }
};

pub const FrontFace = enum {
    clockwise,
    counter_clockwise,

    fn toVk(self: FrontFace) vk.FrontFace {
        return switch (self) {
            .clockwise => .clockwise,
            .counter_clockwise => .counter_clockwise,
        };
    }
};

pub const PolygonMode = enum {
    fill,
    line,
    point,

    fn toVk(self: PolygonMode) vk.PolygonMode {
        return switch (self) {
            .fill => .fill,
            .line => .line,
            .point => .point,
        };
    }
};

pub const BlendFactor = enum {
    zero,
    one,
    src_color,
    one_minus_src_color,
    dst_color,
    one_minus_dst_color,
    src_alpha,
    one_minus_src_alpha,
    dst_alpha,
    one_minus_dst_alpha,

    fn toVk(self: BlendFactor) vk.BlendFactor {
        return switch (self) {
            .zero => .zero,
            .one => .one,
            .src_color => .src_color,
            .one_minus_src_color => .one_minus_src_color,
            .dst_color => .dst_color,
            .one_minus_dst_color => .one_minus_dst_color,
            .src_alpha => .src_alpha,
            .one_minus_src_alpha => .one_minus_src_alpha,
            .dst_alpha => .dst_alpha,
            .one_minus_dst_alpha => .one_minus_dst_alpha,
        };
    }
};

pub const BlendOp = enum {
    add,
    subtract,
    reverse_subtract,
    min,
    max,

    fn toVk(self: BlendOp) vk.BlendOp {
        return switch (self) {
            .add => .add,
            .subtract => .subtract,
            .reverse_subtract => .reverse_subtract,
            .min => .min,
            .max => .max,
        };
    }
};

pub const BlendConfig = struct {
    enabled: bool = false,
    src_color: BlendFactor = .one,
    dst_color: BlendFactor = .zero,
    color_op: BlendOp = .add,
    src_alpha: BlendFactor = .one,
    dst_alpha: BlendFactor = .zero,
    alpha_op: BlendOp = .add,

    /// Standard alpha blending: src.rgb * src.a + dst.rgb * (1 - src.a)
    pub const alpha_blend = BlendConfig{
        .enabled = true,
        .src_color = .src_alpha,
        .dst_color = .one_minus_src_alpha,
        .color_op = .add,
        .src_alpha = .one,
        .dst_alpha = .zero,
        .alpha_op = .add,
    };

    /// Additive blending: src.rgb + dst.rgb
    pub const additive = BlendConfig{
        .enabled = true,
        .src_color = .one,
        .dst_color = .one,
        .color_op = .add,
        .src_alpha = .one,
        .dst_alpha = .one,
        .alpha_op = .add,
    };
};

pub const Pipeline = struct {
    vulkan: *rendering.EggyVulkanInterface,
    handle: vk.Pipeline,
    layout: vk.PipelineLayout,

    pub fn deinit(self: *Pipeline) void {
        self.vulkan.device.destroyPipeline(self.handle, null);
        self.vulkan.device.destroyPipelineLayout(self.layout, null);
    }

    /// Start building a new graphics pipeline.
    pub fn builder(vulkan: *rendering.EggyVulkanInterface) PipelineBuilder {
        return PipelineBuilder.init(vulkan);
    }
};

pub const PipelineBuilder = struct {
    vulkan: *rendering.EggyVulkanInterface,

    // Shader stages
    vert_module: ?vk.ShaderModule = null,
    vert_entry: [*:0]const u8 = "main",
    frag_module: ?vk.ShaderModule = null,
    frag_entry: [*:0]const u8 = "main",

    // Input assembly
    topology_value: Topology = .triangle_list,
    primitive_restart: bool = false,

    // Rasterization
    polygon_mode_value: PolygonMode = .fill,
    cull_mode_value: CullMode = .back,
    front_face_value: FrontFace = .clockwise,
    line_width_value: f32 = 1.0,
    depth_clamp: bool = false,
    rasterizer_discard: bool = false,

    // Depth/stencil
    depth_test: bool = false,
    depth_write: bool = false,

    // Multisampling
    samples: u8 = 1,

    // Color blending
    blend_config: BlendConfig = .{},

    // Dynamic state
    dynamic_viewport: bool = true,
    dynamic_scissor: bool = true,

    // Color format (defaults to swapchain format)
    color_format_override: ?vk.Format = null,

    pub fn init(vulkan: *rendering.EggyVulkanInterface) PipelineBuilder {
        return .{ .vulkan = vulkan };
    }

    /// Set the vertex shader module and entry point.
    pub fn vertexShader(self: *PipelineBuilder, module: vk.ShaderModule, entry: [*:0]const u8) *PipelineBuilder {
        self.vert_module = module;
        self.vert_entry = entry;
        return self;
    }

    /// Set the fragment shader module and entry point.
    pub fn fragmentShader(self: *PipelineBuilder, module: vk.ShaderModule, entry: [*:0]const u8) *PipelineBuilder {
        self.frag_module = module;
        self.frag_entry = entry;
        return self;
    }

    /// Set primitive topology (triangle_list, line_list, etc.)
    pub fn topology(self: *PipelineBuilder, t: Topology) *PipelineBuilder {
        self.topology_value = t;
        return self;
    }

    /// Set polygon rasterization mode (fill, line, point)
    pub fn polygonMode(self: *PipelineBuilder, mode: PolygonMode) *PipelineBuilder {
        self.polygon_mode_value = mode;
        return self;
    }

    /// Set face culling mode
    pub fn cullMode(self: *PipelineBuilder, mode: CullMode) *PipelineBuilder {
        self.cull_mode_value = mode;
        return self;
    }

    /// Set front face winding order
    pub fn frontFace(self: *PipelineBuilder, face: FrontFace) *PipelineBuilder {
        self.front_face_value = face;
        return self;
    }

    /// Set line width for line rendering
    pub fn lineWidth(self: *PipelineBuilder, width: f32) *PipelineBuilder {
        self.line_width_value = width;
        return self;
    }

    /// Enable/disable depth testing
    pub fn depthTest(self: *PipelineBuilder, enabled: bool) *PipelineBuilder {
        self.depth_test = enabled;
        return self;
    }

    /// Enable/disable depth writing
    pub fn depthWrite(self: *PipelineBuilder, enabled: bool) *PipelineBuilder {
        self.depth_write = enabled;
        return self;
    }

    /// Set color blending configuration
    pub fn blend(self: *PipelineBuilder, config: BlendConfig) *PipelineBuilder {
        self.blend_config = config;
        return self;
    }

    /// Override the color attachment format (defaults to swapchain format)
    pub fn colorFormat(self: *PipelineBuilder, format: vk.Format) *PipelineBuilder {
        self.color_format_override = format;
        return self;
    }

    /// Build the pipeline. Returns error if shaders are not set.
    pub fn build(self: *PipelineBuilder) !Pipeline {
        const vert = self.vert_module orelse return error.MissingVertexShader;
        const frag = self.frag_module orelse return error.MissingFragmentShader;

        // Shader stages
        const stages = [_]vk.PipelineShaderStageCreateInfo{
            .{
                .stage = .{ .vertex_bit = true },
                .module = vert,
                .p_name = self.vert_entry,
            },
            .{
                .stage = .{ .fragment_bit = true },
                .module = frag,
                .p_name = self.frag_entry,
            },
        };

        const vertex_input = vk.PipelineVertexInputStateCreateInfo{
            .vertex_binding_description_count = 0,
            .p_vertex_binding_descriptions = null,
            .vertex_attribute_description_count = 0,
            .p_vertex_attribute_descriptions = null,
        };

        const input_assembly = vk.PipelineInputAssemblyStateCreateInfo{
            .topology = self.topology_value.toVk(),
            .primitive_restart_enable = if (self.primitive_restart) .true else .false,
        };

        const viewport_state = vk.PipelineViewportStateCreateInfo{
            .viewport_count = 1,
            .scissor_count = 1,
        };

        const rasterization = vk.PipelineRasterizationStateCreateInfo{
            .depth_clamp_enable = if (self.depth_clamp) .true else .false,
            .rasterizer_discard_enable = if (self.rasterizer_discard) .true else .false,
            .polygon_mode = self.polygon_mode_value.toVk(),
            .cull_mode = self.cull_mode_value.toVk(),
            .front_face = self.front_face_value.toVk(),
            .depth_bias_enable = .false,
            .depth_bias_constant_factor = 0.0,
            .depth_bias_clamp = 0.0,
            .depth_bias_slope_factor = 0.0,
            .line_width = self.line_width_value,
        };

        const sample_flag: vk.SampleCountFlags = switch (self.samples) {
            1 => .{ .@"1_bit" = true },
            2 => .{ .@"2_bit" = true },
            4 => .{ .@"4_bit" = true },
            8 => .{ .@"8_bit" = true },
            16 => .{ .@"16_bit" = true },
            32 => .{ .@"32_bit" = true },
            else => .{ .@"1_bit" = true },
        };
        const multisampling = vk.PipelineMultisampleStateCreateInfo{
            .rasterization_samples = sample_flag,
            .sample_shading_enable = .false,
            .min_sample_shading = 1.0,
            .alpha_to_coverage_enable = .false,
            .alpha_to_one_enable = .false,
        };

        const color_blend_attachment = vk.PipelineColorBlendAttachmentState{
            .blend_enable = if (self.blend_config.enabled) .true else .false,
            .src_color_blend_factor = self.blend_config.src_color.toVk(),
            .dst_color_blend_factor = self.blend_config.dst_color.toVk(),
            .color_blend_op = self.blend_config.color_op.toVk(),
            .src_alpha_blend_factor = self.blend_config.src_alpha.toVk(),
            .dst_alpha_blend_factor = self.blend_config.dst_alpha.toVk(),
            .alpha_blend_op = self.blend_config.alpha_op.toVk(),
            .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
        };

        const color_blending = vk.PipelineColorBlendStateCreateInfo{
            .logic_op_enable = .false,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = @ptrCast(&color_blend_attachment),
            .blend_constants = .{ 0.0, 0.0, 0.0, 0.0 },
        };

        var dynamic_states_buf: [2]vk.DynamicState = undefined;
        var dynamic_count: u32 = 0;
        if (self.dynamic_viewport) {
            dynamic_states_buf[dynamic_count] = .viewport;
            dynamic_count += 1;
        }
        if (self.dynamic_scissor) {
            dynamic_states_buf[dynamic_count] = .scissor;
            dynamic_count += 1;
        }
        const dynamic_state = vk.PipelineDynamicStateCreateInfo{
            .dynamic_state_count = dynamic_count,
            .p_dynamic_states = &dynamic_states_buf,
        };

        const layout_info = vk.PipelineLayoutCreateInfo{
            .set_layout_count = 0,
            .push_constant_range_count = 0,
        };
        const layout = try self.vulkan.device.createPipelineLayout(&layout_info, null);
        errdefer self.vulkan.device.destroyPipelineLayout(layout, null);

        const color_fmt = self.color_format_override orelse self.vulkan.swapchain.surface_format.format;
        const rendering_info = vk.PipelineRenderingCreateInfo{
            .color_attachment_count = 1,
            .p_color_attachment_formats = @ptrCast(&color_fmt),
            .depth_attachment_format = .undefined,
            .stencil_attachment_format = .undefined,
            .view_mask = 0,
        };

        const pipeline_info = vk.GraphicsPipelineCreateInfo{
            .p_next = @ptrCast(&rendering_info),
            .stage_count = 2,
            .p_stages = &stages,
            .p_vertex_input_state = &vertex_input,
            .p_input_assembly_state = &input_assembly,
            .p_viewport_state = &viewport_state,
            .p_rasterization_state = &rasterization,
            .p_multisample_state = &multisampling,
            .p_color_blend_state = &color_blending,
            .p_dynamic_state = &dynamic_state,
            .layout = layout,
            .render_pass = .null_handle,
            .subpass = 0,
            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = -1,
        };

        var handle: vk.Pipeline = undefined;
        _ = try self.vulkan.device.createGraphicsPipelines(
            .null_handle,
            1,
            @ptrCast(&pipeline_info),
            null,
            @ptrCast(&handle),
        );

        return Pipeline{
            .vulkan = self.vulkan,
            .handle = handle,
            .layout = layout,
        };
    }
};
