const std = @import("std");
const luexpress = @import("luuxp");
const main_demo = @import("demos/main_demo.zig");
const proto_demo = @import("demos/proto_demo.zig");
const app = luexpress.app;

pub fn main(init: std.process.Init) !void {

    var iter = init.minimal.args.iterate();
    _ = iter.skip();

    if (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "proto")) {
            // run the prototype demo.
            try proto_demo.run(std.heap.smp_allocator, init.io);
        }
        else if (std.mem.eql(u8, arg, "main")) {
            // run the main demo.
            try app.run(main_demo.State, main_demo.Events, std.heap.smp_allocator, init.io);
        }
        else {
            std.debug.print("Invalid argument. Expected 'proto' or 'main'.\n", .{ });
        }
    }
    else {
        std.debug.print("Please provide one argument ('proto' or 'main').\n", .{ });
    }
}