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
        var c_string = try native.AllocedCString.init(title);
        defer c_string.deinit();

        const w = c.SDL_CreateWindow(c_string.value, @intCast(size[0]), @intCast(size[1]), 0) orelse {
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

pub fn deinit(self: *@This()) void {
    log.info("Releasing window '{s}'.", .{ c.SDL_GetWindowTitle(self.handle) });
    c.SDL_DestroyWindow(self.handle);
}

pub fn setTitle(self: *@This(), title: []const u8) !void {

    var c_string = try native.AllocedCString.init(title);
    defer c_string.deinit();
    const ok = c.SDL_SetWindowTitle(self.handle, c_string.value);

    if (!ok) {
        log.err("Failed to update the window's title to '{s}'.", .{ title });
        return WindowError.ResourceUpdateFailure;
    }

    log.info("Updated window title to '{s}'.", .{ title });
}

pub fn setSize(self: *@This(), size: @Vector(2, u32)) !void {
    const ok = c.SDL_SetWindowSize(self.handle, size[0], size[1]);

    if (!ok) {
        log.err("Failed to update the window's size to {}x{}.", .{ size[0], size[1] });
        return WindowError.ResourceUpdateFailure;
    }

    log.info("Updated window size to {}x{}.", .{ size[0], size[1] });
}