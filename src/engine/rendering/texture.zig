pub const zigimg = @import("zigimg");

const std = @import("std");
const rendering = @import("vulkan.zig");
const cmd = @import("command.zig");
const vk = @import("vulkan");
const debug = @import("debug.zig");
const Context = @import("../ctx.zig").Context;

pub const Texture = struct {
    e_vulkan: *rendering.EggyVulkanInterface,

    texture: vk.Image = undefined,
    texture_mem: vk.DeviceMemory = undefined,

    image_view: vk.ImageView = undefined,
    sampler: vk.Sampler = undefined,

    pub fn initFromFile(ctx: *Context, e_vulkan: *rendering.EggyVulkanInterface, file: std.Io.File, label: ?[*:0]const u8) !Texture {
        var read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
        var image = try zigimg.Image.fromFile(ctx.proc_init.gpa, ctx.proc_init.io, file, read_buffer[0..]);
        defer image.deinit(ctx.proc_init.gpa);
        return Texture.init(e_vulkan, &image, label);
    }

    pub fn initFromMemory(ctx: *Context, e_vulkan: *rendering.EggyVulkanInterface, data: []const u8, label: ?[*:0]const u8) !Texture {
        var image = try zigimg.Image.fromMemory(ctx.proc_init.gpa, data);
        defer image.deinit(ctx.proc_init.gpa);
        return Texture.init(e_vulkan, &image, label);
    }

    fn init(e_vulkan: *rendering.EggyVulkanInterface, image: *zigimg.Image, label: ?[*:0]const u8) !Texture {
        try image.convert(e_vulkan.allocator, .rgba32);
        const image_size: u64 = @intCast(image.imageByteSize());

        var self = Texture{
            .e_vulkan = e_vulkan,
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

        try createImageView(&self, .r8g8b8a8_srgb);
        try createSampler(&self);

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

    fn createImageView(self: *@This(), format: vk.Format) !void {
        const view_info = vk.ImageViewCreateInfo {
            .image = self.texture,
            .view_type = .@"2d",
            .format = format,
            .subresource_range = .{ 
                .aspect_mask = .{ .color_bit = true }, 
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        };

        self.image_view = try self.e_vulkan.device.createImageView(&view_info, null);
    }

    fn createSampler(self: *@This()) !void {
        const properties = self.e_vulkan.instance.getPhysicalDeviceProperties(self.e_vulkan.pdev);
        const sampler_info = vk.SamplerCreateInfo {
            .mag_filter = .linear,
            .min_filter = .linear,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
            .anisotropy_enable = .true,
            .max_anisotropy = properties.limits.max_sampler_anisotropy,
            .border_color = .int_opaque_black,
            .unnormalized_coordinates = .false,
            .compare_enable = .false,
            .compare_op = .always,
            .mipmap_mode = .linear,
            .mip_lod_bias = 0.0,
            .min_lod = 0.0,
            .max_lod = 0.0,
        };
        self.sampler = try self.e_vulkan.device.createSampler(&sampler_info, null);
    }

    pub fn deinit(self: *@This()) void {
        self.e_vulkan.device.destroySampler(self.sampler, null);
        self.e_vulkan.device.destroyImageView(self.image_view, null);

        self.e_vulkan.device.destroyImage(self.texture, null);
        self.e_vulkan.device.freeMemory(self.texture_mem, null);
    }
};