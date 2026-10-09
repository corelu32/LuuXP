const std = @import("std");
const luexpress = @import("luuxp");
const GpuDevice = luexpress.GpuDevice;
const RuntimeSettings = luexpress.RuntimeSettings;

pub fn main(init: std.process.Init) !void {

    const State = struct {
        allocator: std.mem.Allocator,
        io: std.Io,
    };

    const Events = struct {
        pub fn onInit(allocator: std.mem.Allocator, io: std.Io) !State {

            try luexpress.useSubSystems(&.{ });

            return .{
                .allocator = allocator,
                .io = io,
            };
        }

        pub fn onEvent(_: *State) !void {

        }

        pub fn useSettings(_: *State) RuntimeSettings {
            return .{
                .target_fps = 60,
                .vsync_enabled = false
            };
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