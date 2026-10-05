const std = @import("std");
const luuxp = @import("luuxp");
const Application = luuxp.Application;

pub fn main(init: std.process.Init) !void {
    try Application.run(
        .{
            .allocator = std.heap.smp_allocator,
            .io = init.io
        },
        struct {
            pub fn onInit(app: *Application) !void {

                try app.useSubSystems(&.{
                    
                });

                app.settings = .{
                    .target_fps = 60.0
                };
            }

            pub fn onUpdate(_: *Application, dt: f64) !void {
                std.debug.print("FPS: {}\n", .{ 1 / dt });
            }

            pub fn onRender(_: *Application, _: f64) !void {

            }

            pub fn onQuit(_: *Application) !void {

            }
        });
}