const std = @import("std");
const luexpress = @import("luuxp");
const c = luexpress.native.c;



pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    var running = true;
    var event: c.SDL_Event = undefined;

    _ = io;



    // INITIALIZE SDL, CREATE WINDOW, CREATE GPU DEVICE.
    _ = c.SDL_Init(c.SDL_INIT_VIDEO);

    const window = if (c.SDL_CreateWindow("PROTO_DEMO", 800, 600, 0)) |w|
        w
        else return error.WindowInitError;

    const gpu_device = if (c.SDL_CreateGPUDevice(
        c.SDL_GPU_SHADERFORMAT_SPIRV,
        true,
        null)) |d| d else return error.GpuDeviceInitError;
    
    _ = c.SDL_ClaimWindowForGPUDevice(gpu_device, window);



    // LOAD VERTEX AND FRAGMENT SHADER.
    // Keep your entry_point names matching your slangc script strings!
    const vert_shader = try load_shader(allocator, gpu_device, .{
        .path        = "./demo/.assets/Proto.vert.spv",
        .stage       = c.SDL_GPU_SHADERSTAGE_VERTEX,
        .entry_point = "main",

        .num_uniform_buffers  = 0,
        .num_storage_buffers  = 0,
        .num_storage_textures = 0,
        .num_samplers         = 0,
    });

    const frag_shader = try load_shader(allocator, gpu_device, .{
        .path        = "./demo/.assets/Proto.frag.spv",
        .stage       = c.SDL_GPU_SHADERSTAGE_FRAGMENT,
        .entry_point = "main",

        .num_uniform_buffers  = 0,
        .num_storage_buffers  = 0,
        .num_storage_textures = 0,
        .num_samplers         = 0,
    });

    const swapchain_format = c.SDL_GetGPUSwapchainTextureFormat(gpu_device, window);

    // Keep array layout address stable in scope
    const color_targets = [_]c.SDL_GPUColorTargetDescription{.{
        .format = swapchain_format,
        .blend_state = .{
            .enable_blend = false,
            .enable_color_write_mask = true,
            .color_write_mask = 0xF, // Write out to RGBA
        },
    }};

    // Zero out pipeline config block to clear extension fields (.props) completely
    var pipeline_create_info = std.mem.zeroes(c.SDL_GPUGraphicsPipelineCreateInfo);
    
    pipeline_create_info.vertex_shader = vert_shader;
    pipeline_create_info.fragment_shader = frag_shader;
    pipeline_create_info.primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST;

    pipeline_create_info.vertex_input_state = .{
        .num_vertex_buffers = 0,
        .vertex_buffer_descriptions = null,
        .num_vertex_attributes = 0,
        .vertex_attributes = null,
    };

    pipeline_create_info.target_info = .{
        .num_color_targets = 1,
        .color_target_descriptions = &color_targets,
        .has_depth_stencil_target = false,
        .depth_stencil_format = c.SDL_GPU_TEXTUREFORMAT_D16_UNORM,
    };

    pipeline_create_info.rasterizer_state = .{
        .fill_mode = c.SDL_GPU_FILLMODE_FILL,
        .cull_mode = c.SDL_GPU_CULLMODE_NONE,
        .front_face = c.SDL_GPU_FRONTFACE_CLOCKWISE,
    };

    pipeline_create_info.multisample_state = .{
        .sample_count = c.SDL_GPU_SAMPLECOUNT_1,
        .sample_mask = 0,
    };

    pipeline_create_info.depth_stencil_state = .{
        .enable_depth_test = false,
        .enable_depth_write = false,
        .enable_stencil_test = false,
    };

    const pipeline = if (c.SDL_CreateGPUGraphicsPipeline(gpu_device, &pipeline_create_info)) |p| p
        else return error.PipelineCreateError;
    
    _ = pipeline;



    // APPLICATION RENDER LOOP.
    while (running) {
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,
                else => { }
            }
        }
    }

    // FREE RESOURCES.
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

    const bytecode = try read_file_bytes(allocator, info.path, false);
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

pub fn read_file_bytes(allocator: std.mem.Allocator, path: []const u8, add_padding: bool) ![]u8 {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    const stream = c.SDL_IOFromFile(path_z, "rb");
    if (stream == null) { return error.IoError; }
    defer _ = c.SDL_CloseIO(stream);

    const actual_size: usize = @intCast(c.SDL_GetIOSize(stream));
    
    // Determine target size (round up to nearest multiple of 4 if padding requested)
    const target_size = if (add_padding) 
        (actual_size + 3) & ~@as(usize, 3) 
    else 
        actual_size;

    // Allocate using u32 to force 4-byte alignment on the memory address
    const size_words = target_size / 4 + (if (target_size % 4 != 0) @as(usize, 1) else 0);
    const buffer_u32 = try allocator.alloc(u32, size_words);
    
    // Safely cast to standard u8 slice without breaking the 4-byte alignment guarantee
    const buffer_u8 = std.mem.sliceAsBytes(buffer_u32);

    // Read the actual file payload directly into the buffer
    _ = c.SDL_ReadIO(stream, buffer_u8.ptr, actual_size);

    // If padded, zero out any trailing padding bytes so they aren't garbage memory
    if (add_padding and target_size > actual_size) {
        @memset(buffer_u8[actual_size..target_size], 0);
    }

    // Return the slice sliced exactly to the target size (retaining padding if enabled)
    return buffer_u8[0..target_size];
}