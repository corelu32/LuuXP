const std = @import("std");
const luexpress = @import("luuxp");

const FileRepo         = luexpress.FileRepo;
const FileStream       = luexpress.FileStream;
const Window           = luexpress.Window;
const GpuDevice        = luexpress.GpuDevice;
const CommandBuffer    = luexpress.CommandBuffer;
const Shader           = luexpress.Shader;
const UniformBuffer    = luexpress.UniformBuffer;
const GraphicsPipeline = luexpress.GraphicsPipeline;
const input            = luexpress.input;
const app              = luexpress.app;
const SubSystem        = app.SubSystem;
const RuntimeSettings  = app.RuntimeSettings;
const RuntimeContext   = app.RuntimeContext;

const State = struct { 
    allocator   : std.mem.Allocator,
    io          : std.Io,
    file_repo   : *FileRepo,
    window      : *Window,
    gpu_device  : *GpuDevice,
    vert_shader : *Shader,
    frag_shader : *Shader,
    uniforms    : *UniformBuffer,
    pipeline    : *GraphicsPipeline,
    tick        : u64 = 0,
};

const Events = struct {
    pub fn onInit(allocator: std.mem.Allocator, io: std.Io, settings: *RuntimeSettings) !State {
        
        settings.target_fps = 60;
        settings.vsync_enabled = false;

        try app.loadSubSystems(&.{ SubSystem.Video });

        // Create the window.
        const window = try allocator.create(Window);
        errdefer allocator.destroy(window);
        window.* = try Window.init(allocator, "Luexpress Demo (0 FPS)", .{ 800, 600 });

        // Create the GPU device.
        var gpu_device = try allocator.create(GpuDevice);
        errdefer allocator.destroy(gpu_device);
        gpu_device.* = try GpuDevice.init(allocator, false);
        try gpu_device.claimWindow(window);

        // Create the file repo.
        const file_repo = try allocator.create(FileRepo);
        errdefer allocator.destroy(file_repo);
        file_repo.* = try FileRepo.init(io, "./demo/.assets", .ParentDirectory);

        // Create the vertex shader.
        const vert_shader = try allocator.create(Shader);
        errdefer allocator.destroy(vert_shader);
        vert_shader.* = try Shader.initFromPath(allocator, gpu_device,
        .{
            .repo = file_repo,
            .path = "Demo.vert.spv",
            .stage = .Vertex,
            .entry = "VertexMain"
        });
        
        // Create the fragment shader.
        const frag_shader = try allocator.create(Shader);
        errdefer allocator.destroy(frag_shader);
        frag_shader.* = try Shader.initFromPath(allocator, gpu_device,
        .{
            .repo = file_repo,
            .path = "Demo.frag.spv",
            .stage = .Fragment,
            .entry = "FragmentMain"
        });

        const uniforms = try allocator.create(UniformBuffer);
        errdefer allocator.destroy(uniforms);
        uniforms.* = try vert_shader.getUniformBuffer("Uniforms");

        const pipeline = try allocator.create(GraphicsPipeline);
        errdefer allocator.destroy(pipeline);

        // Create the Graphics pipeline.
        pipeline.* = try GraphicsPipeline.init(allocator, gpu_device, .{
            .vertex_shader = vert_shader,
            .fragment_shader = frag_shader,
            .primitive_type = .TriangleList,

            .rasterizer = .{
                .cull_mode = .None,
                .fill_mode = .Fill,
                .winding_order = .Clockwise,
                .depth_bias = null,
                .enable_depth_clip = true
            },

            .multisample = .{
                .sample_count = gpu_device.claimed_windows.get(window).?.sample_count.selected.value,
                .enable_alpha_to_coverage = false,
            },

            .depth_stencil = .{
                .depth_test = .{
                    .on_compare = .Less,
                    .enable_writes = true
                },
                .stencil_test = null,
            },

            .color_targets = &[_]GraphicsPipeline.ColorTarget {
                .{
                    .blending = .{
                        .color = .{
                            .source_factor = .SourceAlpha,
                            .dest_factor   = .OneMinusSourceAlpha,
                            .on_blend      = .Add
                        },
                        .alpha = .{
                            .source_factor = .SourceAlpha,
                            .dest_factor   = .OneMinusSourceAlpha,
                            .on_blend      = .Add
                        }
                    },
                    .color_write_mask = null,
                    .format = .{ .Float = .Rgba16 }, // FIX: Should match MSAA sample count!!
                }
            }
        });

        return .{
            .allocator   = allocator,
            .io          = io,
            .window      = window,
            .gpu_device  = gpu_device,
            .file_repo   = file_repo,
            .vert_shader = vert_shader,
            .frag_shader = frag_shader,
            .uniforms    = uniforms,
            .pipeline    = pipeline,
        };
    }

    pub fn onKeyPress(ctx: *RuntimeContext(State), key: input.Keycode) !void {
        if (key == .Escape) {
            ctx.quit();
        }
    }
    
    pub fn onUpdate(ctx: *RuntimeContext(State), dt: f64) !void {
        // Update window title to include FPS every 60 frames.
        {
            if (ctx.state.tick % 60 == 0) {
                var buffer: [64]u8 = undefined;
                const title = try std.fmt.bufPrint(&buffer, "Luexpress Demo ({} FPS)", .{ @round(1 / dt) });
                try ctx.state.window.setTitle(title);
                ctx.state.tick = 1;
            }

            ctx.state.tick += 1;
        }
    }

    pub fn onRender(ctx: *RuntimeContext(State), _: f64) !void {
        var commands = try ctx.state.gpu_device.acquireCommandBuffer();

        try commands.submit();
    }

    pub fn onQuit(ctx: *RuntimeContext(State)) !void {
        const allocator   = ctx.state.allocator;
        const window      = ctx.state.window;
        const gpu_device  = ctx.state.gpu_device;
        const file_repo   = ctx.state.file_repo;
        const vert_shader = ctx.state.vert_shader;
        const frag_shader = ctx.state.frag_shader;

        try gpu_device.waitForIdle();
        gpu_device.deinit();
        window.deinit();

        allocator.destroy(vert_shader);
        allocator.destroy(frag_shader);
        allocator.destroy(window);
        allocator.destroy(gpu_device);
        allocator.destroy(file_repo);
    }
};

pub fn main(init: std.process.Init) !void {
    try app.run(State, Events, std.heap.smp_allocator, init.io);
}