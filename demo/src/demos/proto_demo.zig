const std = @import("std");
const luexpress = @import("luuxp");
const c = luexpress.native.c;

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    var running = true;
    var event: c.SDL_Event = undefined;

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
    
    const pipeline_create_info: c.SDL_GPUGraphicsPipelineCreateInfo = .{
        .vertex_shader = vert_shader,
        .fragment_shader = frag_shader,
        
        // Topology settings: we are drawing a triangle list
        .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,

        // Vertex input layout: Zero out because the shader handles everything via SV_VertexID
        .vertex_input_state = .{
            .num_vertex_buffers = 0,
            .vertex_buffer_descriptions = null,
            .num_vertex_attributes = 0,
            .vertex_attributes = null,
        },

        // Target render attachment specs (Usually matching your swapchain texture format)
        .target_info = .{
            .num_color_targets = 1,
            .color_target_descriptions = &[_]c.SDL_GPUColorTargetDescription{.{
                .format = c.SDL_GetGPUSwapchainTextureFormat(gpu_device, window),
                .blend_state = .{
                    .enable_blend = false, // Blending off for a solid color triangle
                },
            }},
            .has_depth_stencil_target = false,
            .depth_stencil_format = c.SDL_GPU_TEXTUREFORMAT_D16_UNORM, // Irrelevant when disabled
        },

        // Standard rasterizer options for basic 2D drawing
        .rasterizer_state = .{
            .fill_mode = c.SDL_GPU_FILLMODE_FILL,
            .cull_mode = c.SDL_GPU_CULLMODE_NONE, // Draw even if winding order flips
            .front_face = c.SDL_GPU_FRONTFACE_CLOCKWISE,
        },

        // Multisample settings (No MSAA)
        .multisample_state = .{
            .sample_count = c.SDL_GPU_SAMPLECOUNT_1,
            .sample_mask = 0,
        },

        // Depth settings disabled for a flat triangle
        .depth_stencil_state = .{
            .enable_depth_test = false,
            .enable_depth_write = false,
            .enable_stencil_test = false,
        },
    };

    _ = pipeline_create_info;

    // const pipeline = if (c.SDL_CreateGPUGraphicsPipeline(gpu_device, &pipeline_create_info)) |p| p
    //     else return error.PipelineCreateError;
    
    // _ = pipeline;

    while (running) {
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,
                else => { }
            }
        }
    }

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