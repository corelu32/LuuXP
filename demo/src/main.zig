const std = @import("std");
const luexpress = @import("luuxp");
const SubSystem = luexpress.SubSystem;
const Window = luexpress.Window;
const GpuDevice = luexpress.GpuDevice;
const RuntimeSettings = luexpress.RuntimeSettings;

pub fn main(init: std.process.Init) !void {

    const State = struct {
        allocator: std.mem.Allocator,
        io: std.Io,
        window: Window,
        gpu_device: GpuDevice,
    };

    const Events = struct {
        pub fn onInit(allocator: std.mem.Allocator, io: std.Io) !State {

            try luexpress.loadSubSystems(&.{ SubSystem.Video });
            var window = try Window.init(allocator, "Main Window", .{ 800, 600 });
            var gpu_device = try GpuDevice.init(allocator, false);
            try gpu_device.claimWindow(&window);

            return .{
                .allocator = allocator,
                .io = io,
                .window = window,
                .gpu_device = gpu_device
            };
        }

        pub fn onQuerySettings(_: *State) RuntimeSettings {
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

        pub fn onRender(_: *State, _: f64) !void {

        }

        pub fn onQuit(state: *State) !void {
            try state.gpu_device.waitForIdle();
            state.gpu_device.deinit();
            state.window.deinit();
        }
    };

    try luexpress.run(State, Events, .{ std.heap.smp_allocator, init.io });
}