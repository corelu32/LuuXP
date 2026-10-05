const std = @import("std");
const luuxp = @import("luuxp");
const Application = luuxp.Application;

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.smp_allocator;
    var app = Application.init(allocator, init.io);

    try app.run(struct {
        pub fn onInit() !void {
            std.debug.print("Initialized application.\n", .{ });
        }

        pub fn onUpdate(dt: f64) !void {
            std.debug.print("FPS: {}\n", .{ 1 / dt });
        }

        pub fn onRender(_: f64) !void {

        }

        pub fn onQuit() !void {

        }
    });
}