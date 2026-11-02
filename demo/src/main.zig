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
    file_repo   : FileRepo,
    window      : Window,
    gpu_device  : GpuDevice,
    vert_shader : Shader,
    frag_shader : Shader,
    uniforms    : UniformBuffer,
    pipeline    : GraphicsPipeline,
    tick        : u64 = 0,
};

const Events = struct {
    pub fn onInit(ctx: *RuntimeContext(State), allocator: std.mem.Allocator, io: std.Io) !void {
        
        ctx.settings.target_fps = 60;
        ctx.settings.vsync_enabled = false;

        try app.loadSubSystems(&.{ SubSystem.Video });

        ctx.state.window = try Window.init(allocator, "Luexpress Demo (0 FPS)", .{ 800, 600 });

        ctx.state.gpu_device = try GpuDevice.init(allocator, false);
        try ctx.state.gpu_device.claimWindow(&ctx.state.window);

        ctx.state.file_repo = try FileRepo.init(io, "./demo/.assets", .ParentDirectory);

        // Create the vertex shader.
        ctx.state.vert_shader = try Shader.initFromPath(allocator, &ctx.state.gpu_device,
        .{
            .repo = &ctx.state.file_repo,
            .path = "Demo.vert.spv",
            .stage = .Vertex,
            .entry = "VertexMain"
        });
        
        // Create the fragment shader.
        ctx.state.frag_shader = try Shader.initFromPath(allocator, &ctx.state.gpu_device,
        .{
            .repo = &ctx.state.file_repo,
            .path = "Demo.frag.spv",
            .stage = .Fragment,
            .entry = "FragmentMain"
        });

        ctx.state.uniforms = try ctx.state.vert_shader.getUniformBuffer("Uniforms");

        // Create the Graphics pipeline.
        // pipeline.* = try GraphicsPipeline.init(allocator, gpu_device, .{
        //     .vertex_shader = vert_shader,
        //     .fragment_shader = frag_shader,
        //     .primitive_type = .TriangleList,

        //     .rasterizer = .{
        //         .cull_mode = .None,
        //         .fill_mode = .Fill,
        //         .winding_order = .Clockwise,
        //         .depth_bias = null,
        //         .enable_depth_clip = true
        //     },

        //     .multisample = .{
        //         .sample_count = gpu_device.claimed_windows.get(window).?.sample_count.selected.value,
        //         .enable_alpha_to_coverage = false,
        //     },

        //     .depth_stencil = .{
        //         .depth_test = .{
        //             .on_compare = .Less,
        //             .enable_writes = true
        //         },
        //         .stencil_test = null,
        //     },

        //     .color_targets = &[_]GraphicsPipeline.ColorTarget {
        //         .{
        //             .blending = .{
        //                 .color = .{
        //                     .source_factor = .SourceAlpha,
        //                     .dest_factor   = .OneMinusSourceAlpha,
        //                     .on_blend      = .Add
        //                 },
        //                 .alpha = .{
        //                     .source_factor = .SourceAlpha,
        //                     .dest_factor   = .OneMinusSourceAlpha,
        //                     .on_blend      = .Add
        //                 }
        //             },
        //             .color_write_mask = null,
        //             .format = .{ .Float = .Rgba16 }, // FIX: Should match MSAA sample count!!
        //         }
        //     }
        // });
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
        var window      = ctx.state.window;
        var gpu_device  = ctx.state.gpu_device;

        try gpu_device.waitForIdle();
        gpu_device.deinit();
        window.deinit();
    }
};

pub fn main(init: std.process.Init) !void {
    try app.run(State, Events, std.heap.smp_allocator, init.io);
}