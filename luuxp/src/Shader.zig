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
    StorageTexture,
    SampledTexture,
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

pub const ShaderError = error {
    ResourceNotSupported,
};



const ResourceParserInfo = struct {
    count: u32 = 0,
    binding_counter: u32 = 0,
};

const ShaderParserInfo = struct {
    spv_module: *SpirvModule,

    uniform_buffers: ResourceParserInfo = .{},
    storage_buffers: ResourceParserInfo = .{},
    storage_textures: ResourceParserInfo = .{},
    sampled_textures: ResourceParserInfo = .{},
    samplers: ResourceParserInfo = .{},
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

    var spv_module = try SpirvModule.init(allocator, bytecode);
    defer spv_module.deinit();

    try parseBytecode(&spv_module, info.stage);

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

fn parseBytecode(spv_module: *SpirvModule, stage: ShaderStage) !void {

    var ctx: ShaderParserInfo = .{
        .spv_module = spv_module
    };

    const desc_count = spv_module.descriptors.len;

    // Pass 01: Accumulate the totals of each resource type.
    for (0..desc_count) |i| {
        const descriptor = &spv_module.descriptors[i];

        switch (descriptor.type) {
            .UniformBuffer => ctx.uniform_buffers.count  += 1,
            .StorageBuffer => ctx.storage_buffers.count  += 1,
            .StorageImage  => ctx.storage_textures.count += 1,
            .SampledImage  => ctx.storage_textures.count += 1,
            .Sampler       => ctx.samplers.count         += 1,

            else => {
                log.err("Cannot parse unsupported shader resource '{s}'.", .{ @tagName(descriptor.type) });
                return ShaderError.ResourceNotSupported;
            }
        }
    }

    // Pass 02: Mutate space/binding values to comply with SDL's expectations.
    for (0..desc_count) |i| {
        const descriptor = &spv_module.descriptors[i];

        var space_num : u32 = undefined; // Resource's space number.
        var bind_num  : u32 = undefined; // Resource's binding number.
        var slot_num  : u32 = undefined; // SDL's slot number.

        // Assign space number based on the descriptor type & shader stage.
        switch (descriptor.type) {
            
            // These resources share the same space numbers.
            .StorageBuffer,
            .StorageImage,
            .SampledImage,
            .Sampler => {
                // Assign 'space' based on the stage.
                switch (stage) {
                    .Vertex   => space_num = 0,
                    .Fragment => space_num = 2,
                    .Compute  => {}
                }
            },

            // Uniform buffers exist within their own spaces.
            .UniformBuffer => {
                // Assign 'space' based on the stage.
                switch (stage) {
                    .Vertex   => space_num = 1,
                    .Fragment => space_num = 3,
                    .Compute  => {}
                }
            },

            else => {
                log.err("Cannot parse unsupported shader resource '{s}'.", .{ @tagName(descriptor.type) });
                return ShaderError.ResourceNotSupported;
            }
        }

        // Assign slot/binding numbers based on the descriptor type.
        switch (descriptor.type) {

            .Sampler => {
                const offset = 0;

                slot_num = ctx.samplers.binding_counter + 0;
                bind_num = ctx.samplers.binding_counter + offset;

                ctx.samplers.binding_counter += 1;
            },

            .SampledImage => {
                const offset = 0;

                slot_num = ctx.sampled_textures.binding_counter + 0;
                bind_num = ctx.sampled_textures.binding_counter + offset;

                ctx.sampled_textures.binding_counter += 1;
            },

            .StorageImage => {
                const offset = ctx.samplers.count;

                slot_num = ctx.storage_textures.binding_counter + 0;
                bind_num = ctx.storage_textures.binding_counter + offset;

                ctx.storage_textures.binding_counter += 1;
            },

            .StorageBuffer => {
                const offset = ctx.samplers.count
                             + ctx.storage_textures.count;
                
                slot_num = ctx.storage_buffers.binding_counter + 0;
                bind_num = ctx.storage_buffers.binding_counter + offset;

                ctx.storage_buffers.binding_counter += 1;
            },

            // Uniform buffers do not share spaces with any other resources.
            .UniformBuffer => {
                const offset = 0;

                slot_num = ctx.uniform_buffers.binding_counter + 0;
                bind_num = ctx.uniform_buffers.binding_counter + offset;

                ctx.uniform_buffers.binding_counter += 1;
            },

            else => {
                log.err("Cannot parse unsupported shader resource '{s}'.", .{ @tagName(descriptor.type) });
                return ShaderError.ResourceNotSupported;
            }
        }

        log.debug("{s} '{s}' mapped to: (space={}, binding={}, slot={})", .{
            @tagName(descriptor.type),
            descriptor.name,
            space_num,
            bind_num,
            slot_num
        });

        try descriptor.updateBindingNumbers(space_num, bind_num);
    }
}