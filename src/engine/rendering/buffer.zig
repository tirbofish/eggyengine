const vk = @import("vulkan");
const rendering = @import("vulkan.zig");
const pipeline = @import("pipeline.zig");
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

pub const MemoryPropertyFlags = struct {
    DeviceLocal: bool = false,
    HostVisible: bool = false,
    HostCoherent: bool = false,
    HostCached: bool = false,
    LazilyAllocated: bool = false,
    Protected: bool = false,
    DeviceCoherent: bool = false,
    DeviceUncached: bool = false,

    pub fn toVk(self: MemoryPropertyFlags) vk.MemoryPropertyFlags {
        return .{
            .device_local_bit = self.DeviceLocal,
            .host_visible_bit = self.HostVisible,
            .host_coherent_bit = self.HostCoherent,
            .host_cached_bit = self.HostCached,
            .lazily_allocated_bit = self.LazilyAllocated,
            .protected_bit = self.Protected,
            .device_coherent_bit_amd = self.DeviceCoherent,
            .device_uncached_bit_amd = self.DeviceUncached,
        };
    }
};

/// Find a suitable memory type index for the given requirements.
pub fn findMemoryType(e_vulkan: *rendering.EggyVulkanInterface, typeFilter: u32, properties: vk.MemoryPropertyFlags) ?u32 {
    const memProps = e_vulkan.instance.getPhysicalDeviceMemoryProperties(e_vulkan.pdev);
    for (0..memProps.memory_type_count) |i| {
        if ((typeFilter & (@as(u32, 1) << @intCast(i))) != 0 and
            memProps.memory_types[i].property_flags.contains(properties))
        {
            return @intCast(i);
        }
    }
    return null;
}

/// A raw GPU buffer without type information
pub const RawBuffer = struct {
    e_vulkan: *rendering.EggyVulkanInterface,
    buffer: vk.Buffer,
    mem: vk.DeviceMemory,
    size: vk.DeviceSize,

    /// Create a raw buffer with the specified size, usage, and memory properties.
    pub fn init(
        e_vulkan: *rendering.EggyVulkanInterface,
        size: vk.DeviceSize,
        usage: BufferUsageFlags,
        mem_properties: MemoryPropertyFlags,
        label: ?[*:0]const u8,
    ) !RawBuffer {
        const buffer_info = vk.BufferCreateInfo{
            .size = size,
            .usage = usage.toVk(),
            .sharing_mode = .exclusive,
        };

        const buffer = try e_vulkan.device.createBuffer(&buffer_info, null);
        rendering.vkSetName(e_vulkan.device, vk.Buffer, buffer, label);
        errdefer e_vulkan.device.destroyBuffer(buffer, null);

        const memRequirements = e_vulkan.device.getBufferMemoryRequirements(buffer);

        const memAllocInfo = vk.MemoryAllocateInfo{
            .allocation_size = memRequirements.size,
            .memory_type_index = findMemoryType(e_vulkan, memRequirements.memory_type_bits, mem_properties.toVk()) orelse return error.NoSuitableMemoryType,
        };

        const mem = try e_vulkan.device.allocateMemory(&memAllocInfo, null);
        errdefer e_vulkan.device.freeMemory(mem, null);

        try e_vulkan.device.bindBufferMemory(buffer, mem, 0);
        try @import("../eggy.zig").logger.tracef("Initialised new buffer '{any}' [flags={any}]", .{label, usage}, @src());
        return RawBuffer{
            .e_vulkan = e_vulkan,
            .buffer = buffer,
            .mem = mem,
            .size = size,
        };
    }

    /// Map the buffer memory and return a pointer to it.
    pub fn map(self: *RawBuffer) !?*anyopaque {
        return try self.e_vulkan.device.mapMemory(self.mem, 0, self.size, .{});
    }

    /// Unmap the buffer memory.
    pub fn unmap(self: *RawBuffer) void {
        self.e_vulkan.device.unmapMemory(self.mem);
    }

    /// Copy data to the buffer. The buffer must be host-visible.
    /// 
    /// This already maps and unmaps the data for you, however you can map yourself with `RawBuffer.map/unmap`. 
    pub fn copyFromSlice(self: *RawBuffer, comptime T: type, data: []const T) !void {
        const mapped = try self.map();
        if (mapped) |ptr| {
            const dest: [*]T = @ptrCast(@alignCast(ptr));
            @memcpy(dest[0..data.len], data);
        }
        self.unmap();
    }

    pub fn deinit(self: RawBuffer) void {
        self.e_vulkan.device.freeMemory(self.mem, null);
        self.e_vulkan.device.destroyBuffer(self.buffer, null);
    }
};


pub fn copyBuffer(e_vulkan: *rendering.EggyVulkanInterface, src: vk.Buffer, dst: vk.Buffer, size: vk.DeviceSize) !void {
    var cmd_buf: vk.CommandBuffer = undefined;
    try e_vulkan.device.allocateCommandBuffers(&.{
        .command_pool = e_vulkan.command_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&cmd_buf));
    defer e_vulkan.device.freeCommandBuffers(e_vulkan.command_pool, 1, @ptrCast(&cmd_buf));

    try e_vulkan.device.beginCommandBuffer(cmd_buf, &.{
        .flags = .{ .one_time_submit_bit = true },
    });

    const copy_region = vk.BufferCopy{
        .src_offset = 0,
        .dst_offset = 0,
        .size = size,
    };
    e_vulkan.device.cmdCopyBuffer(cmd_buf, src, dst, 1, @ptrCast(&copy_region));

    try e_vulkan.device.endCommandBuffer(cmd_buf);

    const submit_info = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&cmd_buf),
    };
    try e_vulkan.device.queueSubmit(e_vulkan.queue.inner, 1, @ptrCast(&submit_info), .null_handle);
    try e_vulkan.device.queueWaitIdle(e_vulkan.queue.inner);
}

pub fn createBuffer(
    e_vulkan: *rendering.EggyVulkanInterface,
    size: vk.DeviceSize,
    usage: BufferUsageFlags,
    mem_properties: MemoryPropertyFlags,
) !struct { buffer: vk.Buffer, mem: vk.DeviceMemory } {
    const raw = try RawBuffer.init(e_vulkan, size, usage, mem_properties);
    return .{ .buffer = raw.buffer, .mem = raw.mem };
}

/// Ensures that the alignment of the struct is suited to multiples of 16 bytes. 
/// 
/// If failure to check, it will result in a compile-time error. 
pub fn checkAlignment(comptime T: type) void {
    if (@sizeOf(T) % 16 != 0) {
        @compileError(std.fmt.comptimePrint("The type '{s}' must be aligned by 16 byte multiples (currently {d}). Use `eggy.math.Padding` to pad and ensure alignment", .{ @typeName(T), @sizeOf(T) }));
    }
}

/// A typed block of memory allocated to the GPU, with support for dirty-state checking. 
pub fn Buffer(comptime T: type) type {
    return struct {
        comptime {
            checkAlignment(T);
        }

        raw: RawBuffer,
        data: []const T,
        dirty: bool,

        /// Initialises a new `Buffer` with the data of a specific type. 
        /// 
        /// Make sure to flush it straight after with `Buffer.flush()`, otherwise you will not see anything.
        pub fn init(e_vulkan: *rendering.EggyVulkanInterface, data: []const T, usage: BufferUsageFlags) !@This() {
            const size: vk.DeviceSize = @sizeOf(T) * data.len;

            const raw = try RawBuffer.init(e_vulkan, size, usage, .{
                .HostVisible = true,
                .HostCoherent = true,
            });

            return @This(){
                .raw = raw,
                .data = data,
                .dirty = true,
            };
        }

        /// Initialises a new `Buffer` with custom memory properties.
        pub fn initWithMemoryProperties(
            e_vulkan: *rendering.EggyVulkanInterface,
            data: []const T,
            usage: BufferUsageFlags,
            mem_properties: MemoryPropertyFlags,
        ) !@This() {
            const size: vk.DeviceSize = @sizeOf(T) * data.len;

            const raw = try RawBuffer.init(e_vulkan, size, usage, mem_properties);

            return @This(){
                .raw = raw,
                .data = data,
                .dirty = true,
            };
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

            const mapped = try self.raw.map();
            if (mapped) |ptr| {
                const dest: [*]T = @ptrCast(@alignCast(ptr));
                @memcpy(dest[0..self.data.len], self.data);
            }
            self.raw.unmap();
            self.dirty = false;
        }

        /// Updates the buffer data and marks it as dirty.
        pub fn write(self: *@This(), data: []const T) void {
            self.data = data;
            self.dirty = true;
        }

        pub fn deinit(self: *@This()) void {
            self.raw.e_vulkan.await() catch {};
            self.raw.deinit();
        }
    };
}

pub fn VertexBuffer(comptime T: type) type {
    return struct {
        raw: RawBuffer,
        len: usize,

        pub fn init(e_vulkan: *rendering.EggyVulkanInterface, data: []const T, label: ?[*:0]const u8) !@This() {
            const size: vk.DeviceSize = @sizeOf(T) * data.len;

            var staging = try RawBuffer.init(
                e_vulkan, 
                size, 
                .{ .TransferSrc = true }, 
                .{
                    .HostVisible = true,
                    .HostCoherent = true,
                },
                label
            );
            defer staging.deinit();

            try staging.copyFromSlice(T, data);

            var raw = try RawBuffer.init(e_vulkan, size, .{
                .VertexBuffer = true,
                .TransferDst = true,
            }, .{
                .DeviceLocal = true,
            }, label);
            errdefer raw.deinit();

            try copyBuffer(e_vulkan, staging.buffer, raw.buffer, size);

            return @This(){
                .raw = raw,
                .len = data.len,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.raw.e_vulkan.await() catch {};
            self.raw.deinit();
        }
    };
}

pub fn IndexBuffer(comptime T: type) type {
    return struct {
        raw: RawBuffer,
        len: usize,

        /// T should be u16 or u32.
        pub fn init(e_vulkan: *rendering.EggyVulkanInterface, data: []const T, label: ?[*:0]const u8) !@This() {
            const size: vk.DeviceSize = @sizeOf(T) * data.len;

            var staging = try RawBuffer.init(e_vulkan, size, .{ .TransferSrc = true }, .{
                .HostVisible = true,
                .HostCoherent = true,
            },
            label);
            defer staging.deinit();

            try staging.copyFromSlice(T, data);

            const raw = try RawBuffer.init(e_vulkan, size, .{
                .IndexBuffer = true,
                .TransferDst = true,
            }, .{
                .DeviceLocal = true,
            }, label);
            errdefer raw.deinit();

            try copyBuffer(e_vulkan, staging.buffer, raw.buffer, size);

            return @This(){
                .raw = raw,
                .len = data.len,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.raw.e_vulkan.await() catch {};
            self.raw.deinit();
        }
    };
}

/// In the shader-slang, this would be a `ConstantBuffer<T> foo;`
pub fn UniformBuffer(comptime T: type) type {
    return struct {
        comptime {
            checkAlignment(T);
        }
        raw: RawBuffer,
        mapped: [*]T,

        descriptor_pool: vk.DescriptorPool,
        descriptor_sets: [rendering.EggyVulkanInterface.MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,

        /// Create a uniform buffer bound to a pipeline's descriptor set layout.
        pub fn init(e_vulkan: *rendering.EggyVulkanInterface, p: pipeline.Pipeline, label: ?[*:0]const u8) !@This() {
            const descriptor_set_layout = p.descriptor_set_layout;
            const size: vk.DeviceSize = @sizeOf(T);

            const raw = try RawBuffer.init(e_vulkan, size, .{ .UniformBuffer = true }, .{
                .HostVisible = true,
                .HostCoherent = true,
            }, label);
            errdefer raw.deinit();

            const mapped_ptr = try e_vulkan.device.mapMemory(raw.mem, 0, size, .{});
            const mapped: [*]T = @ptrCast(@alignCast(mapped_ptr));

            const pool_size = vk.DescriptorPoolSize{
                .descriptor_count = rendering.EggyVulkanInterface.MAX_FRAMES_IN_FLIGHT,
                .type = .uniform_buffer,
            };

            const pool_info = vk.DescriptorPoolCreateInfo{
                .flags = .{},
                .max_sets = rendering.EggyVulkanInterface.MAX_FRAMES_IN_FLIGHT,
                .pool_size_count = 1,
                .p_pool_sizes = @ptrCast(&pool_size),
            };

            const descriptor_pool = try e_vulkan.device.createDescriptorPool(&pool_info, null);
            errdefer e_vulkan.device.destroyDescriptorPool(descriptor_pool, null);

            var layouts: [rendering.EggyVulkanInterface.MAX_FRAMES_IN_FLIGHT]vk.DescriptorSetLayout = undefined;
            for (&layouts) |*layout| {
                layout.* = descriptor_set_layout;
            }

            const alloc_info = vk.DescriptorSetAllocateInfo{
                .descriptor_pool = descriptor_pool,
                .descriptor_set_count = rendering.EggyVulkanInterface.MAX_FRAMES_IN_FLIGHT,
                .p_set_layouts = &layouts,
            };

            var descriptor_sets: [rendering.EggyVulkanInterface.MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet = undefined;
            try e_vulkan.device.allocateDescriptorSets(&alloc_info, &descriptor_sets);

            for (0..rendering.EggyVulkanInterface.MAX_FRAMES_IN_FLIGHT) |i| {
                const buffer_info = vk.DescriptorBufferInfo{
                    .buffer = raw.buffer,
                    .offset = 0,
                    .range = @sizeOf(T),
                };

                const descriptor_write = vk.WriteDescriptorSet{
                    .dst_set = descriptor_sets[i],
                    .dst_binding = 0,
                    .dst_array_element = 0,
                    .descriptor_count = 1,
                    .descriptor_type = .uniform_buffer,
                    .p_buffer_info = @ptrCast(&buffer_info),
                    .p_image_info = undefined,
                    .p_texel_buffer_view = undefined,
                };

                e_vulkan.device.updateDescriptorSets(1, @ptrCast(&descriptor_write), 0, null);
            }

            // try logger.tracef("Initialised new UniformBuffer");

            return .{
                .raw = raw,
                .mapped = mapped,
                .descriptor_pool = descriptor_pool,
                .descriptor_sets = descriptor_sets,
            };
        }

        /// Write data to the uniform buffer
        pub fn write(self: *@This(), data: T) void {
            self.mapped[0] = data;
        }

        /// Get a pointer to the mapped data for direct modification.
        pub fn getData(self: *@This()) *T {
            return &self.mapped[0];
        }

        /// Get the descriptor set for the current frame.
        pub fn getDescriptorSet(self: *@This(), frame_index: usize) vk.DescriptorSet {
            return self.descriptor_sets[frame_index];
        }

        pub fn deinit(self: *@This()) void {
            self.raw.e_vulkan.device.destroyDescriptorPool(self.descriptor_pool, null);
            self.raw.e_vulkan.device.unmapMemory(self.raw.mem);
            self.raw.e_vulkan.await() catch {};
            self.raw.deinit();
        }
    };
}