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

const log = std.log.scoped(.Shader);

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

pub fn initFromPath(
    allocator: std.mem.Allocator,
    gpu_device: *GpuDevice,
    file_repo: *FileRepo,
    path: []const u8,
    entry_point: []const u8,
    stage: ShaderStage) !@This() {
    
    var stream = try file_repo.open(path);
    defer stream.close() catch { };
    
    return try init(
        allocator,
        gpu_device,
        &stream,
        entry_point,
        stage);
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

const SpirvContext = struct {

    allocator: std.mem.Allocator,
    module: *native.c.SpvReflectShaderModule = undefined,

    resources: struct {
        count: u32 = 0,
        descriptors: []?*native.c.SpvReflectDescriptorBinding = undefined,

        samplers: ShaderParserInfo = .{},
        sampled_images: ShaderParserInfo = .{},
        storage_buffers: ShaderParserInfo = .{},
        uniform_buffers: ShaderParserInfo = .{},
        texel_storage_buffer: ShaderParserInfo = .{},

    } = .{},

    pub fn init(allocator: std.mem.Allocator, bytecode: []u8) !@This() {
        
        var context: @This() = .{
            .module = undefined,
            .allocator = allocator,
            .resources = .{}
        };

        context.module = try allocator.create(native.c.SpvReflectShaderModule);
        errdefer allocator.destroy(context.module);

        // Create the SPIR-V reflection module.
        if (native.c.spvReflectCreateShaderModule(
            bytecode.len,
            bytecode.ptr,
            context.module) != native.c.SPV_REFLECT_RESULT_SUCCESS
        ) {
            log.err("Failed to create SPIR-V module.", .{});
            return error.SpirvModuleError;
        }
        errdefer {
            native.c.spvReflectDestroyShaderModule(context.module);
        }
        
        // Query the top-level descriptor count.
        if (native.c.spvReflectEnumerateDescriptorBindings(
            context.module,
            &context.resources.count,
            null) != native.c.SPV_REFLECT_RESULT_SUCCESS
        ) {
            log.err("Failed to query SPIR-V descriptor binding count.", .{});
            return error.SpirvModuleError;
        }

        // Allocate the array of descriptor binding pointers.
        context.resources.descriptors = try allocator.alloc(
            ?*native.c.SpvReflectDescriptorBinding,
            context.resources.count);
        errdefer {
            allocator.free(context.resources.descriptors);
        }
        
        // Populate the descriptor bindings.
        if (native.c.spvReflectEnumerateDescriptorBindings(
            context.module,
            &context.resources.count,
            context.resources.descriptors.ptr) != native.c.SPV_REFLECT_RESULT_SUCCESS
        ) {
            log.err("Failed to populate SPIR-V descriptor bindings.", .{});
            return error.SpirvModuleError;
        }

        log.debug("Found {} descriptors.", .{ context.resources.count });
        return context;
    }

    pub fn getRootDescriptor(self: *@This(), index: u32) !*native.c.SpvReflectDescriptorBinding {
        if (index >= self.resources.descriptors.len) {
            log.err("Descriptor index out of bounds.", .{ });
            return error.IndexOutOfBounds;
        }
        
        return self.resources.descriptors[index] orelse {
            log.err("Descriptor is null.", .{});
            return error.DescriptorIsNull;
        };
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.resources.descriptors);
        native.c.spvReflectDestroyShaderModule(self.module);
        self.allocator.destroy(self.module);
    }
};