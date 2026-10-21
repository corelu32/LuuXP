const std = @import("std");
const luexpress = @import("luuxp");

const FileRepo        = luexpress.FileRepo;
const FileStream      = luexpress.FileStream;
const Window          = luexpress.Window;
const GpuDevice       = luexpress.GpuDevice;
const CommandBuffer   = luexpress.CommandBuffer;
const Shader          = luexpress.Shader;
const SubSystem       = application.SubSystem;
const input           = luexpress.input;
const application     = luexpress.application;
const RuntimeSettings = application.RuntimeSettings;
const RuntimeContext  = application.RuntimeContext;

const State = struct {
    allocator   : std.mem.Allocator,
    io          : std.Io,
    file_repo   : FileRepo,
    window      : Window,
    gpu_device  : GpuDevice,
    vert_shader : Shader,
    frag_shader : Shader,
    tick        : u64 = 0,
};

const Events = struct {
    pub fn onInit(allocator: std.mem.Allocator, io: std.Io, settings: *RuntimeSettings) !State {
        
        settings.target_fps = 60;
        settings.vsync_enabled = false;

        try application.loadSubSystems(&.{ SubSystem.Video });

        var window = try Window.init(allocator, "Luexpress Demo (0 FPS)", .{ 800, 600 });

        var gpu_device = try GpuDevice.init(allocator, false);

        try gpu_device.claimWindow(&window);

        var file_repo = try FileRepo.init(io, "./demo/.assets", .ParentDirectory);

        const vert_shader = try Shader.initFromPath(
            allocator,
            &gpu_device,
            &file_repo,
            "Demo.vert.spv",
            "VertexMain",
            .Vertex);
        
        const frag_shader = try Shader.initFromPath(
            allocator,
            &gpu_device,
            &file_repo,
            "Demo.frag.spv",
            "FragmentMain",
            .Fragment);

        return .{
            .allocator   = allocator,
            .io          = io,
            .window      = window,
            .gpu_device  = gpu_device,
            .file_repo   = file_repo,
            .vert_shader = vert_shader,
            .frag_shader = frag_shader
        };
    }

    pub fn onKeyPress(_: *RuntimeContext(State), key: input.Keycode) !void {
        if (key == .Escape) {
            std.debug.print("Escape pressed!", .{ });
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
        try ctx.state.gpu_device.waitForIdle();
        ctx.state.gpu_device.deinit();
        ctx.state.window.deinit();
    }
};

pub fn main(init: std.process.Init) !void {
    try application.run(State, Events, std.heap.smp_allocator, init.io);
}