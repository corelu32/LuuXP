const std = @import("std");

pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_image/SDL_image.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
    @cInclude("SDL3_mixer/SDL_mixer.h");
    @cInclude("physfs.h");
    @cInclude("spirv_reflect.h");
});

const NativeError = error { ValueIsZero, ValueIsNull, ValueIsFalse };

pub fn runWithResult(value: anytype) NativeError!@TypeOf(value) {
    const T = @TypeOf(value);

    switch (@typeInfo(T)) {

        .int, .comptime_int => {
            if (value == 0) return NativeError.ValueIsZero;
            return value;
        },

        .bool => {
            if (!value) return NativeError.ValueIsFalse;
            return value;
        },

        .pointer => {
            if (value == null) return NativeError.ValueIsNull;
            return value;
        },

        else => @compileError("tryrun: unsupported type " ++ @typeName(T)),
    }
}

pub fn run(value: anytype) NativeError!void {
    const T = @TypeOf(value);

    switch (@typeInfo(T)) {

        .int, .comptime_int => {
            if (value == 0) return NativeError.ValueIsZero;
        },

        .bool => {
            if (!value) return NativeError.ValueIsFalse;
        },

        .pointer => {
            if (value == null) return NativeError.ValueIsNull;
        },

        else => @compileError("tryrun: unsupported type " ++ @typeName(T)),
    }
}

pub const CString = struct {
    z_string: [*c]const u8,

    pub fn init(value: []const u8) !@This() {
        const span = try std.heap.c_allocator.dupeZ(u8, value);

        return .{
            .z_string = span.ptr,
        };
    }

    pub fn deinit(self: *@This()) void {
        std.heap.c_allocator.free(std.mem.span(self.z_string));
    }
};