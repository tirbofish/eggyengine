const rendering = @import("vulkan.zig");
const vk = @import("vulkan");

pub const Shader = struct {
    e_vulkan: *rendering.EggyVulkanInterface,
    module: vk.ShaderModule,

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
