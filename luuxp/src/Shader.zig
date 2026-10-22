const std = @import("std");
const native = @import("native.zig");
const FileRepo = @import("FileRepo.zig");
const FileStream = @import("FileStream.zig");
const GpuDevice = @import("GpuDevice.zig");
const UniformBuffer = @import("UniformBuffer.zig");

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