const vk = @import("vulkan");
const rendering = @import("vulkan.zig");
const std = @import("std");

pub const BufferUsageFlags = struct {
    TransferSrc: bool = false,
    TransferDst: bool = false,
    UniformTexelBuffer: bool = false,
    StorageTexelBuffer: bool = false,
    UniformBuffer: bool = false,
    StorageBuffer: bool = false,
    IndexBuffer: bool = false,
    VertexBuffer: bool = false,
    IndirectBuffer: bool = false,
    ConditionalRendering: bool = false,
    ShaderBindingTable: bool = false,
    TransformFeedbackBuffer: bool = false,
    TransformFeedbackCounterBuffer: bool = false,
    VideoDecodeSrc: bool = false,
    VideoDecodeDst: bool = false,
    VideoEncodeDst: bool = false,
    VideoEncodeSrc: bool = false,
    ShaderDeviceAddress: bool = false,
    AccelerationStructureBuildInputReadOnly: bool = false,
    AccelerationStructureStorage: bool = false,
    SamplerDescriptorBuffer: bool = false,
    ResourceDescriptorBuffer: bool = false,
    MicromapBuildInputReadOnly: bool = false,
    MicromapStorage: bool = false,
    ExecutionGraphScratch: bool = false,
    PushDescriptorsDescriptorBuffer: bool = false,
    TileMemory: bool = false,
    DescriptorHeap: bool = false,

    pub fn toVk(self: BufferUsageFlags) vk.BufferUsageFlags {
        return .{
            .transfer_src_bit = self.TransferSrc,
            .transfer_dst_bit = self.TransferDst,
            .uniform_texel_buffer_bit = self.UniformTexelBuffer,
            .storage_texel_buffer_bit = self.StorageTexelBuffer,
            .uniform_buffer_bit = self.UniformBuffer,
            .storage_buffer_bit = self.StorageBuffer,
            .index_buffer_bit = self.IndexBuffer,
            .vertex_buffer_bit = self.VertexBuffer,
            .indirect_buffer_bit = self.IndirectBuffer,
            .conditional_rendering_bit_ext = self.ConditionalRendering,
            .shader_binding_table_bit_khr = self.ShaderBindingTable,
            .transform_feedback_buffer_bit_ext = self.TransformFeedbackBuffer,
            .transform_feedback_counter_buffer_bit_ext = self.TransformFeedbackCounterBuffer,
            .video_decode_src_bit_khr = self.VideoDecodeSrc,
            .video_decode_dst_bit_khr = self.VideoDecodeDst,
            .video_encode_dst_bit_khr = self.VideoEncodeDst,
            .video_encode_src_bit_khr = self.VideoEncodeSrc,
            .shader_device_address_bit = self.ShaderDeviceAddress,
            .acceleration_structure_build_input_read_only_bit_khr = self.AccelerationStructureBuildInputReadOnly,
            .acceleration_structure_storage_bit_khr = self.AccelerationStructureStorage,
            .sampler_descriptor_buffer_bit_ext = self.SamplerDescriptorBuffer,
            .resource_descriptor_buffer_bit_ext = self.ResourceDescriptorBuffer,
            .micromap_build_input_read_only_bit_ext = self.MicromapBuildInputReadOnly,
            .micromap_storage_bit_ext = self.MicromapStorage,
            .execution_graph_scratch_bit_amdx = self.ExecutionGraphScratch,
            .push_descriptors_descriptor_buffer_bit_ext = self.PushDescriptorsDescriptorBuffer,
            .tile_memory_bit_qcom = self.TileMemory,
            .descriptor_heap_bit_ext = self.DescriptorHeap,
        };
    }
};

/// A block of memory allocated to the GPU, with support for dirty-state checking. 
pub fn Buffer(comptime T: type) type {
    return struct {
        e_vulkan: *rendering.EggyVulkanInterface,
        buffer: vk.Buffer,
        mem: vk.DeviceMemory,
        data: []const T,
        size: vk.DeviceSize,
        dirty: bool,

        /// Initialises a new `Buffer` with the data of a specific type. 
        /// 
        /// Make sure to flush it straight after with `Buffer.flush()`, otherwise you will not see anything.
        pub fn init(e_vulkan: *rendering.EggyVulkanInterface, data: []const T, usage: BufferUsageFlags) !@This() {
            var self: @This() = undefined;
            self.size = @sizeOf(T) * data.len;
            self.data = data;
            self.dirty = true;

            const buffer_info = vk.BufferCreateInfo{
                .size = self.size,
                .usage = usage.toVk(),
                .sharing_mode = .exclusive,
            };

            self.buffer = try e_vulkan.device.createBuffer(&buffer_info, null);
            self.e_vulkan = e_vulkan;

            const memRequirements = e_vulkan.device.getBufferMemoryRequirements(self.buffer);

            const memAllocInfo = vk.MemoryAllocateInfo{
                .allocation_size = memRequirements.size,
                .memory_type_index = findMemoryType(&self, memRequirements.memory_type_bits, .{
                    .host_visible_bit = true,
                    .host_coherent_bit = true,
                }) orelse return error.NoSuitableMemoryType,
            };

            self.mem = try e_vulkan.device.allocateMemory(&memAllocInfo, null);
            try e_vulkan.device.bindBufferMemory(self.buffer, self.mem, 0);

            return self;
        }

        /// Marks the buffer as dirty, so the next flush() will write data to GPU memory.
        pub fn markDirty(self: *@This()) void {
            self.dirty = true;
        }

        /// Returns whether the buffer has pending changes to write.
        pub fn isDirty(self: *@This()) bool {
            return self.dirty;
        }

        /// Writes data to GPU memory only if the buffer is dirty.
        /// 
        /// This function can be placed in your update function without any consequences. 
        pub fn flush(self: *@This()) !void {
            if (!self.dirty) return;

            const mapped = try self.e_vulkan.device.mapMemory(self.mem, 0, self.size, .{});
            if (mapped) |ptr| {
                const dest: [*]T = @ptrCast(@alignCast(ptr));
                @memcpy(dest[0..self.data.len], self.data);
            }
            self.e_vulkan.device.unmapMemory(self.mem);
            self.dirty = false;
        }

        /// Updates the buffer data and marks it as dirty.
        pub fn write(self: *@This(), data: []const T) void {
            self.data = data;
            self.dirty = true;
        }

        pub fn deinit(self: *@This()) void {
            self.e_vulkan.await() catch {};
            self.e_vulkan.device.freeMemory(self.mem, null);
            self.e_vulkan.device.destroyBuffer(self.buffer, null);
        }

        fn findMemoryType(self: *@This(), typeFilter: u32, properties: vk.MemoryPropertyFlags) ?u32 {
            const memProps = self.e_vulkan.instance.getPhysicalDeviceMemoryProperties(self.e_vulkan.pdev);
            for (0..memProps.memory_type_count) |i| {
                if ((typeFilter & (@as(u32, 1) << @intCast(i))) != 0 and
                    memProps.memory_types[i].property_flags.contains(properties)) {
                    return @intCast(i);
                }
            }
            return null;
        }
    };
}