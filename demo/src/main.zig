const std = @import("std");
const luuxp = @import("luuxp");
const Application = luuxp.Application;

pub fn main() !void {
    const allocator = std.heap.smp_allocator;
    var app = Application.init(allocator);

    try app.run(struct {
        pub fn onInit() !void {
            std.debug.print("Hello, world.\n", .{});
        }

        pub fn onUpdate(dt: f64) !void {
            _ = dt;
        }

        pub fn onRender(dt: f64) !void {
            _ = dt;
        }

        pub fn onQuit() !void {

        }
    });
}