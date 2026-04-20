const std = @import("std");
const vk = @import("vulkan");

pub inline fn vkSetName(
    device: vk.DeviceProxy,
    comptime T: type,
    handle: T,
    name: ?[*:0]const u8,
) void {
    if (comptime !std.debug.runtime_safety) return; // strips in release

    const object_type = comptime switch (T) {
        vk.CommandBuffer  => vk.ObjectType.command_buffer,
        vk.Image          => vk.ObjectType.image,
        vk.ImageView      => vk.ObjectType.image_view,
        vk.Buffer         => vk.ObjectType.buffer,
        vk.Pipeline       => vk.ObjectType.pipeline,
        vk.RenderPass     => vk.ObjectType.render_pass,
        vk.DescriptorSet  => vk.ObjectType.descriptor_set,
        vk.Queue          => vk.ObjectType.queue,
        vk.Semaphore      => vk.ObjectType.semaphore,
        vk.Fence          => vk.ObjectType.fence,
        vk.Device         => vk.ObjectType.device,
        else => @compileError("Unsupported Vulkan object type: " ++ @typeName(T)),
    };

    const name_info = vk.DebugUtilsObjectNameInfoEXT{
        .object_type   = object_type,
        .object_handle = @intFromEnum(handle),
        .p_object_name = name,
    };

    device.setDebugUtilsObjectNameEXT(&name_info) catch {};
}