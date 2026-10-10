const std = @import("std");
const luexpress = @import("luuxp");

const RuntimeSettings = luexpress.RuntimeSettings;
const FileRepo        = luexpress.FileRepo;
const FileStream      = luexpress.FileStream;
const SubSystem       = luexpress.SubSystem;
const Window          = luexpress.Window;
const GpuDevice       = luexpress.GpuDevice;
const CommandBuffer   = luexpress.CommandBuffer;
const Shader          = luexpress.Shader;

pub fn main(init: std.process.Init) !void {

    const State = struct {
        allocator   : std.mem.Allocator,
        io          : std.Io,
        file_repo   : FileRepo,
        window      : Window,
        gpu_device  : GpuDevice,
        vert_shader : Shader,
        frag_shader : Shader,
    };

    const Events = struct {
        pub fn onInit(allocator: std.mem.Allocator, io: std.Io) !State {

            try luexpress.loadSubSystems(&.{ SubSystem.Video });

            // Create the window and GPU device.
            var window = try Window.init(allocator, "Main Window", .{ 800, 600 });
            var gpu_device = try GpuDevice.init(allocator, false);
            try gpu_device.claimWindow(&window);

            // Initialize the file repo to a local dev directory.
            var file_repo = try FileRepo.init(io, "./demo/.assets", .ParentDirectory);

            // Create the vertex shader.
            const vert_shader = try Shader.initFromPath(
                allocator,
                &gpu_device,
                &file_repo,
                "Demo.vert.spv",
                "VertexMain",
                .Vertex);
            
            // Create the fragment shader.
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

        pub fn useSettings(_: *State) RuntimeSettings {
            return .{
                .target_fps = 60,
                .vsync_enabled = false
            };
        }

        pub fn onKeyPress(_: *State) !void {

        }
        
        pub fn onUpdate(_: *State, _: f64) !void {
            // std.debug.print("FPS: {}\n", .{ 1 / dt });
        }

        pub fn onRender(state: *State, _: f64) !void {
            var commands = try state.gpu_device.acquireCommandBuffer();



            try commands.submit();
        }

        pub fn onQuit(state: *State) !void {
            try state.gpu_device.waitForIdle();
            state.gpu_device.deinit();
            state.window.deinit();
        }
    };

    try luexpress.run(State, Events, .{ std.heap.smp_allocator, init.io });
}