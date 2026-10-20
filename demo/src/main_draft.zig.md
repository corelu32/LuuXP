
# DRAFT COPY
--------------------------------------------------

```zig
const std = @import("std");
const luexpress = @import("luuxp");

const Application     = luexpress.Application;
const RuntimeSettings = luexpress.RuntimeSettings;
const RuntimeContext  = luexpress.RuntimeContext;
const loadSubSystems  = luexpress.loadSubSystems;
const FileRepo        = luexpress.FileRepo;
const FileStream      = luexpress.FileStream;
const SubSystem       = luexpress.SubSystem;
const Keyboard        = luexpress.Keyboard;
const Window          = luexpress.Window;
const GpuDevice       = luexpress.GpuDevice;
const CommandBuffer   = luexpress.CommandBuffer;
const Shader          = luexpress.Shader;

const State = struct {
    allocator    : std.mem.Allocator,
    io           : std.Io,
    file_repo    : FileRepo,
    window       : Window,
    gpu_device   : GpuDevice,
    vert_shader  : Shader,
    frag_shader  : Shader,
    uniforms     : ShaderResource,
    uniform_data : []u8,
    writer       : ShaderBufferWriter,
    tick         : u64 = 0,
};

const Events = struct {
    pub fn onInit(allocator: std.mem.Allocator, io: std.Io, settings: *RuntimeSettings) !State {
        
        settings.target_fps = 60;
        settings.vsync_enabled = false;

        var file_repo = try FileRepo.init(io, "./demo/.assets", .ParentDirectory);

        try loadSubSystems(&.{ SubSystem.Video });
        var window = try Window.init(allocator, "Luexpress Demo (0 FPS)", .{ 800, 600 });

        var gpu_device = try GpuDevice.init(allocator, false);
        try gpu_device.claimWindow(&window);

        const vert_shader = try Shader.initFromPath(allocator, &gpu_device, &file_repo, .{
            .path        = "Demo.vert.spv",
            .stage       = .Vertex,
            .entry_point = "VertexMain",
        });

        const frag_shader = try Shader.initFromPath(allocator, &gpu_device, &file_repo, .{
            .path        = "Demo.frag.spv",
            .stage       = .Fragment,
            .entry_point = "FragmentMain",
        });

        var uniforms = try vert_shader.getResource("Uniforms");
        var uniform_data: []u8 = try uniforms.layout.allocBuffer(allocator);
        var buffer_writer = ResourceBufferWriter.init(allocator);

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

    pub fn onKeyPress(ctx: *RuntimeContext(State), key: Keyboard.KeyCode) !void {
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

    pub fn onRender(ctx: *RuntimeContext(State), dt: f64) !void {
        var command_buffer = try ctx.state.gpu_device.acquireCommandBuffer();

        try ctx.state.writer.write(uniforms.layout, uniform_data, 0,
        .{
            .U_Time   = @as(f32, ctx.state.tick * dt),
            .U_Aspect = @as(f32, 800.0 / 600.0),
            .U_Fov    = @as(f32, 90.0),
            .U_Near   = @as(f32, 0.1),
            .U_Far    = @as(f32, 10.0),
        });

        try ctx.state.uniforms.push(uniform_data);
        Application.draw(.{ .vertices = 3, .objects = 10 });

        try command_buffer.submit();
    }

    pub fn onQuit(ctx: *RuntimeContext(State)) !void {
        try ctx.state.gpu_device.waitForIdle();
        ctx.state.gpu_device.deinit();
        ctx.state.window.deinit();
    }
};

pub fn main(init: std.process.Init) !void {
    try Application.run(State, Events, std.heap.smp_allocator, init.io);
}
```