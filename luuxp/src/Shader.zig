const std = @import("std");
const native = @import("native.zig");
const FileRepo = @import("FileRepo.zig");
const FileStream = @import("FileStream.zig");
const GpuDevice = @import("GpuDevice.zig");
const UniformBuffer = @import("UniformBuffer.zig");
const SpirvModule = @import("SpirvModule.zig");

const log = std.log.scoped(.Shader);

pub const ResourceLayout = @import("ShaderResourceLayout.zig");

pub const ResourceType = enum {
    UniformBuffer,
    StorageBuffer,
    Texture,
    Sampler,
};

pub const ShaderStage = enum {
    Vertex,
    Fragment,
    Compute,
};

pub const InitInfo = struct {
    stream: *FileStream,
    stage: ShaderStage,
    entry: []const u8,
};

pub const InitFromPathInfo = struct {
    repo: *FileRepo,
    path: []const u8,
    stage: ShaderStage,
    entry: []const u8,
};

allocator: std.mem.Allocator,
gpu_device: *GpuDevice,
file_stream: *FileStream,
stage: ShaderStage,

pub fn init(allocator: std.mem.Allocator, gpu_device: *GpuDevice, info: InitInfo) !@This() {
    
    const shader: @This() = .{
        .allocator = allocator,
        .gpu_device = gpu_device,
        .file_stream = info.stream,
        .stage = info.stage,
    };

    const bytecode = try loadBytecode(allocator, info.stream);
    defer allocator.free(bytecode);

    var spirv_module = try SpirvModule.init(allocator, bytecode);
    defer spirv_module.deinit();

    // TODO: Implement entry point!
    _ = info.entry;

    return shader;
}

pub fn initFromPath(allocator: std.mem.Allocator, gpu_device: *GpuDevice, info: InitFromPathInfo) !@This() {
    
    var stream = try info.repo.open(info.path);
    defer stream.close() catch { };
    
    return try init(
        allocator,
        gpu_device,
        .{
            .stream = &stream,
            .stage = info.stage,
            .entry = info.entry
        });
}

pub fn getUniformBuffer(self: *@This(), name: []const u8) !UniformBuffer {
    _ = self;
    _ = name;
    return .{};
}

fn loadBytecode(allocator: std.mem.Allocator, stream: *FileStream) ![]u8 {
    const size = try stream.getSize();
    
    const bytecode = try allocator.alloc(u8, size);
    errdefer allocator.free(bytecode);

    try stream.writeToBuffer(bytecode, size);
    return bytecode;
}

const ShaderParserInfo = struct {
    traversal: struct {
        count: u32 = 0,
        binding_counter: u32 = 0,
    } = .{},
};