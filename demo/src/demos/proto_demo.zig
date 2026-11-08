const std = @import("std");
const luexpress = @import("luuxp");
const c = luexpress.native.c;

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    _ = allocator;
    _ = io;

    // Initialize SDL.
    _ = c.SDL_Init(c.SDL_INIT_VIDEO);

    // Create a window.
    const window = c.SDL_CreateWindow("PROTO_DEMO", 800, 600, 0);

    // Create the GPU device.
    const gpu_device = c.SDL_CreateGPUDevice(
        c.SDL_GPU_SHADERFORMAT_SPIRV,
        true,
        null);
    
    
    
    c.SDL_DestroyGPUDevice(gpu_device);
    c.SDL_DestroyWindow(window);
    c.SDL_Quit();
}