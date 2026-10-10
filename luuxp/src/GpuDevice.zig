const std = @import("std");
const native = @import("native.zig");
const c = native.c;

const log = std.log.scoped(.GpuDevice);

pub const GpuDeviceError = error {
    InitFailure
};

allocator: std.mem.Allocator,
handle: *c.SDL_GPUDevice,

/// Initialize a GPU device.
pub fn init(allocator: std.mem.Allocator, debug_mode: bool) !@This() {

    var device = @This() {
        .allocator = allocator,
        .handle = undefined,
    };

    // Create the GPU device handle.
    {
        const handle = c.SDL_CreateGPUDevice(
            c.SDL_GPU_SHADERFORMAT_SPIRV,
            debug_mode,
            null);
        
        device.handle = handle orelse {
            log.err("Failed to create the GPU device. SDL error: {s}", .{ c.SDL_GetError() });
            return GpuDeviceError.InitFailure;
        };
    }
    errdefer {
        c.SDL_DestroyGPUDevice(device.handle);
    }
    log.info("Created the GPU device.", .{ });

    return device;
}

/// Pause the main thread until the GPU is idle.
pub fn waitForIdle(self: *@This()) !void {
    try native.run(c.SDL_WaitForGPUIdle(self.handle));
}

/// Destroys the GPU device. Do not run subsequent operations
/// afterwards, which will result in undefined behavior.
pub fn deinit(self: *@This()) void {
    c.SDL_DestroyGPUDevice(self.handle);
}