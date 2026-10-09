const std = @import("std");
const native = @import("native.zig");
const GpuDevice = @import("GpuDevice.zig");
const c = native.c;

const WindowError = error {
    ResourceInitFailure,
    ResourceUpdateFailure
};

const log = std.log.scoped(.Window);

allocator: std.mem.Allocator,
handle: *c.SDL_Window,
claimed_by_device: ?*GpuDevice,

pub fn init(allocator: std.mem.Allocator, title: []const u8, size: @Vector(2, u32)) !@This() {

    var window = @This() {
        .allocator = allocator,
        .handle = undefined,
        .claimed_by_device = null,
    };

    // Create the window.
    {
        const w = c.SDL_CreateWindow(std.mem.span(title), size[0], size[1]) orelse {
            log.err("Failed to create the window '{s}''.", .{ title });
            return WindowError.ResourceInitFailure;
        };

        log.info("Created the {}x{} window '{s}'.", .{ size[0], size[1], title });
        window.handle = w;
    }
    errdefer {
        c.SDL_DestroyWindow(window.handle);
    }

    return window;
}