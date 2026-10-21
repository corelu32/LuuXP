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
    file_repo   : *FileRepo,
    window      : *Window,
    gpu_device  : *GpuDevice,
    vert_shader : *Shader,
    frag_shader : *Shader,
    tick        : u64 = 0,
};

const Events = struct {
    pub fn onInit(allocator: std.mem.Allocator, io: std.Io, settings: *RuntimeSettings) !State {
        
        settings.target_fps = 60;
        settings.vsync_enabled = false;

        try application.loadSubSystems(&.{ SubSystem.Video });

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
        vert_shader.* = try Shader.initFromPath(
            allocator,
            gpu_device,
            file_repo,
            "Demo.vert.spv",
            "VertexMain",
            .Vertex);
        
        // Create the fragment shader.
        const frag_shader = try allocator.create(Shader);
        errdefer allocator.destroy(frag_shader);
        frag_shader.* = try Shader.initFromPath(
            allocator,
            gpu_device,
            file_repo,
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
    try application.run(State, Events, std.heap.smp_allocator, init.io);
}