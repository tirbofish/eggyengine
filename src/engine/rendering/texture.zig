pub const zigimg = @import("zigimg");

const std = @import("std");
const rendering = @import("vulkan.zig");
const cmd = @import("command.zig");
const vk = @import("vulkan");
const debug = @import("debug.zig");

pub const Texture = struct {
    e_vulkan: *rendering.EggyVulkanInterface,

    texture: vk.Image,
    texture_mem: vk.DeviceMemory,

    pub fn initFromFile(e_vulkan: *rendering.EggyVulkanInterface, file: *std.fs.File, label: ?[*:0]const u8) !Texture {
        var read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
        var image = try zigimg.Image.fromFile(e_vulkan.allocator, file, read_buffer[0..]);
        defer image.deinit(e_vulkan.allocator);
        return Texture.init(e_vulkan, &image, label);
    }

    pub fn initFromMemory(e_vulkan: *rendering.EggyVulkanInterface, data: []const u8, label: ?[*:0]const u8) !Texture {
        var image = try zigimg.Image.fromMemory(e_vulkan.allocator, data);
        defer image.deinit(e_vulkan.allocator);
        return Texture.init(e_vulkan, &image, label);
    }

    fn init(e_vulkan: *rendering.EggyVulkanInterface, image: *zigimg.Image, label: ?[*:0]const u8) !Texture {
        try image.convert(e_vulkan.allocator, .rgba32);
        const image_size: u64 = @intCast(image.imageByteSize());

        var self = Texture{
            .e_vulkan = e_vulkan,
            .texture = undefined,
            .texture_mem = undefined,
        };

        // ensure staging buffer has image uploaded
        var staging_buffer = try rendering.buffer.RawBuffer.init(
            e_vulkan,
            image_size,
            .{ .TransferSrc = true },
            .{ .HostVisible = true, .HostCoherent = true },
            label,
        );
        defer staging_buffer.deinit();
        try staging_buffer.copyFromSlice(u8, image.rawBytes());

        // then create image
        try self.createImage(
            .r8g8b8a8_srgb, 
            .{
                .width = @intCast(image.width),
                .height = @intCast(image.height),
                .depth = 1
            }, 
            .optimal, 
            .{ 
                .transfer_dst_bit = true, 
                .sampled_bit = true 
            },
            .{ .device_local_bit = true },
            label,
        );

        var command_buffer = try cmd.CommandBuffer.begin(e_vulkan);
        command_buffer.transitionImageLayout(self, .undefined, .transfer_dst_optimal);
        command_buffer.copyBufferToImage(staging_buffer, self, @intCast(image.width), @intCast(image.height));
        command_buffer.transitionImageLayout(self, .transfer_dst_optimal, .shader_read_only_optimal);
        command_buffer.end();

        return self;
    }

    fn createImage(self: *@This(), format: vk.Format, image_size: vk.Extent3D, tiling: vk.ImageTiling, usage: vk.ImageUsageFlags, properties: vk.MemoryPropertyFlags, label: ?[*:0]const u8) !void {
        const image_create_info = vk.ImageCreateInfo {
            .initial_layout = .undefined,
            .image_type = .@"2d",
            .format = format,
            .extent = image_size,
            .mip_levels = 1,
            .array_layers = 1,
            .samples = .{ .@"1_bit" = true },
            .tiling = tiling,
            .usage = usage,
            .sharing_mode = .exclusive,
        };

        self.texture = try self.e_vulkan.device.createImage(&image_create_info, null);
        debug.vkSetName(self.e_vulkan.device, vk.Image, self.texture, label);

        const mem_requirements = self.e_vulkan.device.getImageMemoryRequirements(self.texture);
        const mem_alloc_info = vk.MemoryAllocateInfo {
            .allocation_size = mem_requirements.size,
            .memory_type_index = rendering.buffer.findMemoryType(self.e_vulkan, mem_requirements.memory_type_bits, properties) orelse return error.NoSuitableMemoryType,
        };
        self.texture_mem = try self.e_vulkan.device.allocateMemory(&mem_alloc_info, null);
        try self.e_vulkan.device.bindImageMemory(self.texture, self.texture_mem, 0);
    }

    pub fn deinit(self: *@This()) void {
        self.e_vulkan.device.destroyImage(self.texture, null);
        self.e_vulkan.device.freeMemory(self.texture_mem, null);
    }
};