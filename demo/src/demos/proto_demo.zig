const std = @import("std");
const luexpress = @import("luuxp");
const c = luexpress.native.c;

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    _ = io;

    // Initialize SDL, create a window, and a GPU device.
    _ = c.SDL_Init(c.SDL_INIT_VIDEO);

    const window = if (c.SDL_CreateWindow("PROTO_DEMO", 800, 600, 0)) |w|
        w
        else return error.WindowInitError;

    const gpu_device = if (c.SDL_CreateGPUDevice(
        c.SDL_GPU_SHADERFORMAT_SPIRV,
        true,
        null)) |d| d else return error.GpuDeviceInitError;
    
    _ = c.SDL_ClaimWindowForGPUDevice(gpu_device, window);

    const vert_shader = try load_shader(allocator, gpu_device, .{
        .path        = "./demo/.assets/Demo.vert.spv",
        .stage       = c.SDL_GPU_SHADERSTAGE_VERTEX,
        .entry_point = "VertexMain",

        .num_uniform_buffers  = 0,
        .num_storage_buffers  = 0,
        .num_storage_textures = 0,
        .num_samplers         = 0,
    });

    const frag_shader = try load_shader(allocator, gpu_device, .{
        .path        = "./demo/.assets/Demo.frag.spv",
        .stage       = c.SDL_GPU_SHADERSTAGE_FRAGMENT,
        .entry_point = "FragmentMain",

        .num_uniform_buffers  = 0,
        .num_storage_buffers  = 0,
        .num_storage_textures = 0,
        .num_samplers         = 0,
    });
    
    _ = vert_shader;
    _ = frag_shader;

    c.SDL_DestroyGPUDevice(gpu_device);
    c.SDL_DestroyWindow(window);
    c.SDL_Quit();
}

const LoadShaderInfo = struct {
    path: []const u8,
    entry_point: []const u8,
    num_uniform_buffers: u32,
    num_storage_buffers: u32,
    num_storage_textures: u32,
    num_samplers: u32,
    stage: c.SDL_GPUShaderStage,
};

pub fn load_shader(
    allocator: std.mem.Allocator,
    gpu_device: *c.SDL_GPUDevice,
    info: LoadShaderInfo)
        !*c.SDL_GPUShader {
    
    const entrypoint_z = try allocator.dupeZ(u8, info.entry_point);
    defer allocator.free(entrypoint_z);

    const bytecode = try read_file_bytes(allocator, info.path);
    defer allocator.free(bytecode);

    const payload: c.SDL_GPUShaderCreateInfo = .{
        .code       = bytecode.ptr,
        .code_size  = bytecode.len,
        .format     = c.SDL_GPU_SHADERFORMAT_SPIRV,
        .entrypoint = entrypoint_z.ptr,

        .num_samplers         = info.num_samplers,
        .num_storage_buffers  = info.num_storage_buffers,
        .num_storage_textures = info.num_storage_textures,
        .num_uniform_buffers  = info.num_uniform_buffers,

        .stage = info.stage,
    };

    const shader = c.SDL_CreateGPUShader(gpu_device, &payload);

    if (shader) |s| { return s; }
    else { return error.ShaderCreateError; }
}

pub fn read_file_bytes(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    const stream = c.SDL_IOFromFile(path_z, "rb");

    if (stream == null) { return error.IoError; }
    defer _ = c.SDL_CloseIO(stream);

    const size: usize = @intCast(c.SDL_GetIOSize(stream));
    const buffer = try allocator.alloc(u8, size);
    _ = c.SDL_ReadIO(stream, buffer.ptr, size);

    return buffer;
}