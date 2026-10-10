const std = @import("std");
const native = @import("native.zig");
const Window = @import("Window.zig");
const c = native.c;

const log = std.log.scoped(.GpuDevice);

/// Represents a generic GPU device error.
pub const GpuDeviceError = error {
    InitFailure,
    ClaimFailure,
    RenderTargetFailure,
};

/// Holds information about individually claimed windows.
pub const ClaimedWindowInfo = struct {
    window: *Window,
    sample_count: struct {
        max: struct {
            value: u8,
            object: c.SDL_GPUSampleCount,
        },
        selected: struct {
            value: u8,
            object: c.SDL_GPUSampleCount,
        },
    },
    msaa: struct {
        swapchain_format: c.SDL_GPUTextureFormat,

        // Allocate separate textures for all possible sample counts.
        // Only one will be equiped at a time.
        targets: [4]struct {
            color: ?*c.SDL_GPUTexture,
            depth: ?*c.SDL_GPUTexture,
        }
    },
    clear_color: @Vector(4, f32)
};

allocator: std.mem.Allocator,
handle: *c.SDL_GPUDevice,
claimed_windows: std.AutoHashMap(*Window, ClaimedWindowInfo),

/// Initialize a GPU device.
pub fn init(allocator: std.mem.Allocator, debug_mode: bool) !@This() {

    var device: @This() = .{
        .allocator = allocator,
        .handle = undefined,
        .claimed_windows = std.AutoHashMap(*Window, ClaimedWindowInfo).init(allocator),
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

/// Destroys the GPU device. Do not run subsequent operations
/// afterwards, which will result in undefined behavior.
pub fn deinit(self: *@This()) void {
    c.SDL_DestroyGPUDevice(self.handle);
}

/// Pause the main thread until the GPU is idle.
pub fn waitForIdle(self: *@This()) !void {
    try native.run(c.SDL_WaitForGPUIdle(self.handle));
}

/// Allows the GPU device to claim an existing window.
/// The GPU device tracks a hashmap of claimed windows.
/// The window will also point back to this GPU device.
/// If a window was already claimed, this will return an error.
/// Render targets will be generated automatically.
pub fn claimWindow(self: *@This(), window: *Window) !void {

    if (window.claimed_by_device != null) {
        log.warn("The window titled '{s}' was already claimed!", .{ try window.getTitle() });
        return GpuDeviceError.ClaimFailure;
    }

    var claim_info: ClaimedWindowInfo = .{
        .window = window,
        .sample_count = undefined,
        .msaa = undefined,
        .clear_color = .{ 0.0, 0.0, 0.0, 1.0 }
    };

    window.claimed_by_device = self;
    
    // Claim the window for this GPU device.
    {
        const ok = c.SDL_ClaimWindowForGPUDevice(self.handle, window.handle);

        if (!ok) {
            log.err("Failed to claim window for this GPU device. SDL error: {s}", .{ c.SDL_GetError() });
            return GpuDeviceError.ClaimFailure;
        }

        log.info("GPU device claimed the window successfully.", .{ });
    }
    errdefer {
        c.SDL_ReleaseWindowFromGPUDevice(self.handle, window.handle);
        window.claimed_by_device = null;
    }

    const swap_format = c.SDL_GetGPUSwapchainTextureFormat(self.handle, window.handle);

    for ([_]u8{ 1, 2, 4, 8 }) |sample_count| {
        const sample_object = try convertSampleCountToObject(sample_count);

        const is_supported = c.SDL_GPUTextureSupportsSampleCount(
                                    self.handle,
                                    swap_format,
                                    sample_object);

        // Incompatible sample count found. Assume the subsequent counts are
        // also not supported.
        if (!is_supported) {
            break;
        }
        
        // Found the next highest supported sample count! Capture it.
        claim_info.sample_count.max.value = sample_count;
        claim_info.sample_count.max.object = sample_object;
    }

    log.info("This window supports a maximum sample count of {}.", .{ claim_info.sample_count.max.value });

    // Select the highest sample count by default.
    claim_info.sample_count.selected.value = claim_info.sample_count.max.value;
    claim_info.sample_count.selected.object = claim_info.sample_count.max.object;

    try self.createRenderTargetsForClaimedWindow(&claim_info);
    try self.claimed_windows.put(window, claim_info);
}

/// Create render targets based on existing claimed window info.
/// Stores render target information within the claimed window info's MSAA struct.
fn createRenderTargetsForClaimedWindow(self: *@This(), claim_info: *ClaimedWindowInfo) !void {
    var width: c_int = undefined;
    var height: c_int = undefined;

    const window = claim_info.window;
    const sample_count_obj = claim_info.sample_count.selected.object;

    // Query the window's Size.
    if (!c.SDL_GetWindowSize(window.handle, &width, &height)) {
        log.err("Failed to query the window size. SDL error: {s}", .{ c.SDL_GetError() });
        return GpuDeviceError.RenderTargetFailure;
    }

    claim_info.msaa.swapchain_format = c.SDL_GetGPUSwapchainTextureFormat(
        self.handle,
        window.handle);
    
    for (0..3) |i| {
        // Create the color texture target.
        claim_info.msaa.targets[i].color = c.SDL_CreateGPUTexture(
            self.handle,
            &c.SDL_GPUTextureCreateInfo {
                .type                 = c.SDL_GPU_TEXTURETYPE_2D,
                .format               = claim_info.msaa.swapchain_format,
                .usage                = c.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
                .width                = @intCast(width),
                .height               = @intCast(height),
                .layer_count_or_depth = 1,
                .num_levels           = 1,
                .sample_count         = sample_count_obj,
                .props                = 0
            })
        orelse {
            log.err("Failed to create MSAA color target texture. SDL error: {s}", .{ c.SDL_GetError() });
            return GpuDeviceError.RenderTargetFailure;
        };

        // Create the depth texture target.
        claim_info.msaa.targets[i].depth = c.SDL_CreateGPUTexture(
            self.handle,
            &c.SDL_GPUTextureCreateInfo {
                .type                 = c.SDL_GPU_TEXTURETYPE_2D,
                .format               = c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
                .usage                = c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
                .width                = @intCast(width),
                .height               = @intCast(height),
                .layer_count_or_depth = 1,
                .num_levels           = 1,
                .sample_count         = sample_count_obj,
                .props                = 0
            })
        orelse {
            log.err("Failed to create MSAA depth target texture. SDL error: {s}", .{ c.SDL_GetError() });
            return error.DepthTargetCreateFailure;
        };
    }
}

/// Convert a sample count integer into SDL's sample count enum.
fn convertSampleCountToObject(value: u8) !c.SDL_GPUSampleCount {
    switch (value) {
        1 => return c.SDL_GPU_SAMPLECOUNT_1,
        2 => return c.SDL_GPU_SAMPLECOUNT_2,
        4 => return c.SDL_GPU_SAMPLECOUNT_4,
        8 => return c.SDL_GPU_SAMPLECOUNT_8,

        else => {
            log.err("Invalid sample count {}. Only values 1, 2, 4, and 8 are supported.", .{ value });
            return error.invalid_sample_count;
        }
    }
}