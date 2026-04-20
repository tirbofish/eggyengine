const rendering = @import("vulkan.zig");
const pipeline = @import("pipeline.zig");
const buffer = @import("buffer.zig");
const vk = @import("vulkan");
const colour = @import("../utils/colour.zig");
const std = @import("std");

pub fn colourToVk(self: colour.Colour) vk.ClearValue {
    return .{ .color = .{ .float_32 = .{ self.r, self.g, self.b, self.a } } };
}

/// Load operation for attachments.
pub const LoadOp = enum {
    clear,
    load,
    dont_care,

    fn toVk(self: LoadOp) vk.AttachmentLoadOp {
        return switch (self) {
            .clear => .clear,
            .load => .load,
            .dont_care => .dont_care,
        };
    }
};

/// Store operation for attachments.
pub const StoreOp = enum {
    store,
    dont_care,

    fn toVk(self: StoreOp) vk.AttachmentStoreOp {
        return switch (self) {
            .store => .store,
            .dont_care => .dont_care,
        };
    }
};

/// Color attachment configuration for a render pass.
pub const ColorAttachment = struct {
    clear_color: colour.Colour = colour.Colour.black,
    load_op: LoadOp = .clear,
    store_op: StoreOp = .store,
};

/// Descriptor for configuring a render pass.
pub const RenderPassDescriptor = struct {
    color_attachment: ColorAttachment = .{},
};

/// A scoped render pass that automatically handles Vulkan rendering state.
/// Use with defer to ensure proper cleanup:
/// ```
/// var pass = frame.beginRenderPass(.{ .color_attachment = .{ .clear_color = colour.red } });
/// defer pass.end();
/// pass.setPipeline(my_pipeline);
/// pass.draw(3, 1, 0, 0);
/// ```
pub const RenderPass = struct {
    frame: *Frame,
    ended: bool = false,

    /// Bind a graphics pipeline.
    pub fn setPipeline(self: *RenderPass, p: pipeline.Pipeline) void {
        self.frame.vulkan.device.cmdBindPipeline(self.frame.cmd, .graphics, p.handle);
    }

    /// Bind a vertex buffer.
    pub fn setVertexBuffer(self: *RenderPass, buf: anytype) void {
        const offsets = [_]vk.DeviceSize{0};
        self.frame.vulkan.device.cmdBindVertexBuffers(self.frame.cmd, 0, 1, @ptrCast(&buf.buffer), &offsets);
    }

    /// Draw vertices directly.
    pub fn draw(self: *RenderPass, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void {
        self.frame.vulkan.device.cmdDraw(self.frame.cmd, vertex_count, instance_count, first_vertex, first_instance);
    }

    /// Draw indexed vertices.
    pub fn drawIndexed(self: *RenderPass, index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32) void {
        self.frame.vulkan.device.cmdDrawIndexed(self.frame.cmd, index_count, instance_count, first_index, vertex_offset, first_instance);
    }

    /// Set a custom viewport.
    pub fn setViewport(self: *RenderPass, x: f32, y: f32, width: f32, height: f32) void {
        const viewport = vk.Viewport{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .min_depth = 0.0,
            .max_depth = 1.0,
        };
        self.frame.vulkan.device.cmdSetViewport(self.frame.cmd, 0, 1, @ptrCast(&viewport));
    }

    /// Set a custom scissor rectangle.
    pub fn setScissor(self: *RenderPass, x: i32, y: i32, width: u32, height: u32) void {
        const scissor = vk.Rect2D{
            .offset = .{ .x = x, .y = y },
            .extent = .{ .width = width, .height = height },
        };
        self.frame.vulkan.device.cmdSetScissor(self.frame.cmd, 0, 1, @ptrCast(&scissor));
    }

    /// End the render pass. Called automatically if using defer.
    pub fn end(self: *RenderPass) void {
        if (self.ended) return;
        self.ended = true;

        self.frame.vulkan.device.cmdEndRendering(self.frame.cmd);
        self.frame.transitionImageLayout(
            .color_attachment_optimal,
            .present_src_khr,
            .{ .color_attachment_write_bit = true },
            .{},
            .{ .color_attachment_output_bit = true },
            .{ .bottom_of_pipe_bit = true },
        );
    }
};

pub const Frame = struct {
    pub const AcquireError = error{
        FenceWaitFailed,
        SurfaceLost,
        SwapchainOutOfDate,
        AcquireFailed,
        CommandBufferResetFailed,
        CommandBufferBeginFailed,
    };

    pub const SubmitResult = enum {
        success,
        swapchain_out_of_date,
        swapchain_suboptimal,
    };

    vulkan: *rendering.EggyVulkanInterface,
    cmd: vk.CommandBuffer,
    image_index: u32,
    frame_index: usize,

    /// Acquire the next swapchain image and prepare for recording.
    pub fn acquire(vulkan: *rendering.EggyVulkanInterface) AcquireError!Frame {
        const frame_index = vulkan.current_frame;
        
        const fence_result = vulkan.device.waitForFences(1, @ptrCast(&vulkan.draw_fences[frame_index]), .true, std.math.maxInt(u64)) catch {
            return error.FenceWaitFailed;
        };
        if (fence_result != .success) {
            return error.FenceWaitFailed;
        }
        
        const acquire_result = vulkan.device.acquireNextImageKHR(
            vulkan.swapchain.swapchain,
            std.math.maxInt(u64),
            vulkan.present_completed_semaphores[frame_index],
            .null_handle,
        ) catch |err| {
            return switch (err) {
                error.SurfaceLostKHR => error.SurfaceLost,
                error.OutOfDateKHR => error.SwapchainOutOfDate,
                else => error.AcquireFailed,
            };
        };

        if (acquire_result.result == .error_out_of_date_khr) {
            return error.SwapchainOutOfDate;
        }
        
        vulkan.device.resetFences(1, @ptrCast(&vulkan.draw_fences[frame_index])) catch {
            return error.FenceWaitFailed;
        };

        const cmd_buf = vulkan.command_buffers[frame_index];
        vulkan.device.resetCommandBuffer(cmd_buf, .{}) catch {
            return error.CommandBufferResetFailed;
        };

        vulkan.device.beginCommandBuffer(cmd_buf, &.{
            .flags = .{ .one_time_submit_bit = true },
        }) catch {
            return error.CommandBufferBeginFailed;
        };

        return Frame{
            .vulkan = vulkan,
            .cmd = cmd_buf,
            .image_index = acquire_result.image_index,
            .frame_index = frame_index,
        };
    }

    /// Submit the command buffer and present the frame.
    pub fn submit(self: *Frame) !SubmitResult {
        try self.vulkan.device.endCommandBuffer(self.cmd);

        const frame_index = self.frame_index;
        const image_index = self.image_index;
        
        const wait_stage = vk.PipelineStageFlags{ .color_attachment_output_bit = true };
        const submit_info = vk.SubmitInfo{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&self.vulkan.present_completed_semaphores[frame_index]),
            .p_wait_dst_stage_mask = @ptrCast(&wait_stage),
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&self.cmd),
            .signal_semaphore_count = 1,
            .p_signal_semaphores = @ptrCast(&self.vulkan.render_finished_semaphores.items[image_index]),
        };
        try self.vulkan.device.queueSubmit(self.vulkan.queue.inner, 1, @ptrCast(&submit_info), self.vulkan.draw_fences[frame_index]);

        const present_info = vk.PresentInfoKHR{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&self.vulkan.render_finished_semaphores.items[image_index]),
            .swapchain_count = 1,
            .p_swapchains = @ptrCast(&self.vulkan.swapchain.swapchain),
            .p_image_indices = @ptrCast(&self.image_index),
        };
        
        const present_result = self.vulkan.device.queuePresentKHR(self.vulkan.queue.inner, &present_info) catch |err| {
            return switch (err) {
                error.OutOfDateKHR => .swapchain_out_of_date,
                else => err,
            };
        };
        
        self.vulkan.current_frame = (self.vulkan.current_frame + 1) % rendering.EggyVulkanInterface.MAX_FRAMES_IN_FLIGHT;
        
        if (present_result == .suboptimal_khr) {
            return .swapchain_suboptimal;
        }
        if (self.vulkan.framebuffer_resized) {
            self.vulkan.framebuffer_resized = false;
            return .swapchain_suboptimal;
        }
        
        return .success;
    }

    /// Begin rendering to the swapchain image with the specified clear color.
    pub fn beginRendering(self: *Frame, clear_color: colour.Colour) void {
        self.transitionImageLayout(
            .undefined,
            .color_attachment_optimal,
            .{},
            .{ .color_attachment_write_bit = true },
            .{ .color_attachment_output_bit = true },
            .{ .color_attachment_output_bit = true },
        );

        const attachment_info = vk.RenderingAttachmentInfo{
            .image_view = self.vulkan.swapchain.image_views.items[self.image_index],
            .image_layout = .color_attachment_optimal,
            .resolve_mode = .{},
            .resolve_image_view = .null_handle,
            .resolve_image_layout = .undefined,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = colourToVk(clear_color),
        };

        const rendering_info = vk.RenderingInfo{
            .render_area = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.vulkan.swapchain.swapchain_extent,
            },
            .layer_count = 1,
            .view_mask = 0,
            .color_attachment_count = 1,
            .p_color_attachments = @ptrCast(&attachment_info),
        };

        self.vulkan.device.cmdBeginRendering(self.cmd, &rendering_info);
        self.setFullViewport();
        self.setFullScissor();
    }

    /// Begin a scoped render pass. Use with defer for automatic cleanup:
    /// ```
    /// var pass = frame.beginRenderPass(.{ .color_attachment = .{ .clear_color = colour.red } });
    /// defer pass.end();
    /// pass.setPipeline(my_pipeline);
    /// pass.draw(3, 1, 0, 0);
    /// ```
    pub fn beginRenderPass(self: *Frame, desc: RenderPassDescriptor) RenderPass {
        self.transitionImageLayout(
            .undefined,
            .color_attachment_optimal,
            .{},
            .{ .color_attachment_write_bit = true },
            .{ .color_attachment_output_bit = true },
            .{ .color_attachment_output_bit = true },
        );

        const attachment_info = vk.RenderingAttachmentInfo{
            .image_view = self.vulkan.swapchain.image_views.items[self.image_index],
            .image_layout = .color_attachment_optimal,
            .resolve_mode = .{},
            .resolve_image_view = .null_handle,
            .resolve_image_layout = .undefined,
            .load_op = desc.color_attachment.load_op.toVk(),
            .store_op = desc.color_attachment.store_op.toVk(),
            .clear_value = colourToVk(desc.color_attachment.clear_color),
        };

        const rendering_info = vk.RenderingInfo{
            .render_area = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.vulkan.swapchain.swapchain_extent,
            },
            .layer_count = 1,
            .view_mask = 0,
            .color_attachment_count = 1,
            .p_color_attachments = @ptrCast(&attachment_info),
        };

        self.vulkan.device.cmdBeginRendering(self.cmd, &rendering_info);
        self.setFullViewport();
        self.setFullScissor();

        return RenderPass{
            .frame = self,
        };
    }

    /// End rendering and transition image for presentation.
    pub fn endRendering(self: *Frame) void {
        self.vulkan.device.cmdEndRendering(self.cmd);
        self.transitionImageLayout(
            .color_attachment_optimal,
            .present_src_khr,
            .{ .color_attachment_write_bit = true },
            .{},
            .{ .color_attachment_output_bit = true },
            .{ .bottom_of_pipe_bit = true },
        );
    }

    /// Bind a graphics pipeline.
    pub fn bindPipeline(self: *Frame, p: pipeline.Pipeline) void {
        self.vulkan.device.cmdBindPipeline(self.cmd, .graphics, p.handle);
    }

    /// Draw vertices directly.
    pub fn draw(self: *Frame, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void {
        self.vulkan.device.cmdDraw(self.cmd, vertex_count, instance_count, first_vertex, first_instance);
    }

    /// Transition the swapchain image layout.
    pub fn transitionImageLayout(
        self: *Frame,
        old_layout: vk.ImageLayout,
        new_layout: vk.ImageLayout,
        src_access_mask: vk.AccessFlags2,
        dst_access_mask: vk.AccessFlags2,
        src_stage_mask: vk.PipelineStageFlags2,
        dst_stage_mask: vk.PipelineStageFlags2,
    ) void {
        const barrier = vk.ImageMemoryBarrier2{
            .src_stage_mask = src_stage_mask,
            .src_access_mask = src_access_mask,
            .dst_stage_mask = dst_stage_mask,
            .dst_access_mask = dst_access_mask,
            .old_layout = old_layout,
            .new_layout = new_layout,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = self.vulkan.swapchain.swapchain_images.items[self.image_index],
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };

        const dependency_info = vk.DependencyInfo{
            .image_memory_barrier_count = 1,
            .p_image_memory_barriers = @ptrCast(&barrier),
        };

        self.vulkan.device.cmdPipelineBarrier2(self.cmd, &dependency_info);
    }

    /// Set viewport to cover the full swapchain extent.
    pub fn setFullViewport(self: *Frame) void {
        self.setViewport(0, 0, @floatFromInt(self.vulkan.swapchain.swapchain_extent.width), @floatFromInt(self.vulkan.swapchain.swapchain_extent.height));
    }

    /// Set scissor to cover the full swapchain extent.
    pub fn setFullScissor(self: *Frame) void {
        self.setScissor(0, 0, self.vulkan.swapchain.swapchain_extent.width, self.vulkan.swapchain.swapchain_extent.height);
    }

    /// Set a custom viewport.
    pub fn setViewport(self: *Frame, x: f32, y: f32, width: f32, height: f32) void {
        const viewport = vk.Viewport{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .min_depth = 0.0,
            .max_depth = 1.0,
        };
        self.vulkan.device.cmdSetViewport(self.cmd, 0, 1, @ptrCast(&viewport));
    }

    /// Set a custom scissor rectangle.
    pub fn setScissor(self: *Frame, x: i32, y: i32, width: u32, height: u32) void {
        const scissor = vk.Rect2D{
            .offset = .{ .x = x, .y = y },
            .extent = .{ .width = width, .height = height },
        };
        self.vulkan.device.cmdSetScissor(self.cmd, 0, 1, @ptrCast(&scissor));
    }

    /// Get the current swapchain image.
    pub fn swapchainImage(self: *Frame) vk.Image {
        return self.vulkan.swapchain.swapchain_images.items[self.image_index];
    }

    /// Get the current swapchain image view.
    pub fn swapchainImageView(self: *Frame) vk.ImageView {
        return self.vulkan.swapchain.image_views.items[self.image_index];
    }

    /// Get the swapchain extent.
    pub fn extent(self: *Frame) vk.Extent2D {
        return self.vulkan.swapchain.swapchain_extent;
    }
};