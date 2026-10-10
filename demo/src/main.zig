const std = @import("std");
const luexpress = @import("luuxp");
const Window = luexpress.Window;
const GpuDevice = luexpress.GpuDevice;
const RuntimeSettings = luexpress.RuntimeSettings;

pub fn main(init: std.process.Init) !void {

    const State = struct {
        allocator: std.mem.Allocator,
        io: std.Io,
        window: Window,
    };

    const Events = struct {
        pub fn onInit(allocator: std.mem.Allocator, io: std.Io) !State {

            try luexpress.useSubSystems(&.{ });
            const window = try Window.init(allocator, "Main Window", .{ 800, 600 });

            return .{
                .allocator = allocator,
                .io = io,
                .window = window,
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
        
        pub fn onUpdate(_: *State, dt: f64) !void {
            std.debug.print("FPS: {}\n", .{ 1 / dt });
        }

        pub fn onRender(_: *State, _: f64) !void {

        }

        pub fn onQuit(_: *State) !void {

        }
    };

    try luexpress.run(State, Events, .{ std.heap.smp_allocator, init.io });
}