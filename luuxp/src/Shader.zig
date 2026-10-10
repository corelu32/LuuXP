const std = @import("std");
const native = @import("native.zig");
const FileRepo = @import("FileRepo.zig");
const FileStream = @import("FileStream.zig");
const GpuDevice = @import("GpuDevice.zig");

pub const ShaderStage = enum {
    Vertex,
    Fragment,
    Compute,
};

allocator: std.mem.Allocator,
gpu_device: *GpuDevice,
file_stream: *FileStream,
stage: ShaderStage,

pub fn init(
    allocator: std.mem.Allocator,
    gpu_device: *GpuDevice,
    file_stream: *FileStream,
    entry_point: []const u8,
    stage: ShaderStage) !@This() {
    
    const shader: @This() = .{
        .allocator = allocator,
        .gpu_device = gpu_device,
        .file_stream = file_stream,
        .stage = stage,
    };

    const bytecode = try loadBytecode(allocator, file_stream);
    defer allocator.free(bytecode);

    _ = entry_point;
    return shader;
}

fn loadBytecode(allocator: std.mem.Allocator, stream: *FileStream) ![]u8 {
    const size = try stream.getSize();
    
    const bytecode = try allocator.alloc(u8, size);
    errdefer allocator.free(bytecode);

    try stream.writeToBuffer(bytecode, size);
    return bytecode;
}