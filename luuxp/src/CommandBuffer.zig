const std = @import("std");
const native = @import("native.zig");
const GpuDevice = @import("GpuDevice.zig");

pub const CommandBufferError = error {
    InitFailure,
    CancelFailure,
    SubmitFailure,
};

const log = std.log.scoped(.CommandBuffer);

gpu_device: *GpuDevice,
active_handle: ?*native.c.SDL_GPUCommandBuffer,

pub fn acquire(gpu_device: *GpuDevice) !@This() {
    return .{
        .gpu_device = gpu_device,
        .active_handle = native.c.SDL_AcquireGPUCommandBuffer(gpu_device.handle) orelse {
            log.err("Failed to acquire a command buffer for this GPU device. SDL error: {s}", .{ native.c.SDL_GetError() });
            return CommandBufferError.InitFailure;
        },
    };
}

pub fn submit(self: *@This()) !void {
    if (self.active_handle) |handle| {
        const ok = native.c.SDL_SubmitGPUCommandBuffer(handle);

        if (!ok) {
            log.err("Failed to submit the command buffer. SDL error: {s}", .{ native.c.SDL_GetError() });
            return CommandBufferError.SubmitFailure;
        }

        self.active_handle = null;
    }
    else {
        log.err("There is no command buffer to submit. Was it already submitted?");
        return CommandBufferError.SubmitFailure;
    }
}

pub fn cancel(self: *@This()) !void {
    if (self.active_handle) |handle| {
        const ok = native.c.SDL_CancelGPUCommandBuffer(handle);

        if (!ok) {
            log.err("Failed to cancel the command buffer. SDL error: {s}", .{ native.c.SDL_GetError() });
            return CommandBufferError.CancelFailure;
        }
    }
}