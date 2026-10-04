const std = @import("std");

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) @This() {
    return .{
        .allocator = allocator
    };
}

pub fn run(_: *@This(), iface: anytype) !void {
    try iface.onInit();

    

    try iface.onQuit();
}