const std = @import("std");
const root = @import("../../root.zig");
const native = root.native;
const FileRepo = root.FileRepo;
const FileStream = root.FileStream;
const GpuDevice = root.GpuDevice;
const UniformBuffer = root.UniformBuffer;
const SpirvModule = root.SpirvModule;

const log = std.log.scoped(.Shader);

pub const ResourceLayout = @import("ResourceLayout.zig");

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
    ParseFailure
};

pub const ShaderLayout = struct {
    resource_layouts: std.StringHashMap(ResourceLayout),

    fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .resource_layouts = std.StringHashMap(ResourceLayout).init(allocator)
        };
    }
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

    _ = try parseBytecode(allocator, &spv_module, info.stage);

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

fn parseBytecode(allocator: std.mem.Allocator, spv_module: *SpirvModule, stage: ShaderStage) !ShaderParserResult {

    var ctx: ShaderParserContext = .{
        .spv_module = spv_module
    };

    var result: ShaderParserResult = .{
        .shader_layout = ShaderLayout.init(allocator),
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

        var layout = try ResourceLayout.init(allocator, .{
            .name = descriptor.name,
            .slot = slot_num,
            .space = space_num,
            .binding = bind_num,
            .stage = stage,

            .size = .{
                .compact = descriptor.block.size.compact,
                .actual  = descriptor.block.size.actual,
            },

            .type = switch (descriptor.type) {
                .UniformBuffer => .UniformBuffer,
                .StorageBuffer => .StorageBuffer,
                .StorageImage  => .StorageTexture,
                .SampledImage  => .SampledTexture,
                .Sampler       => .Sampler,

                else => {
                    log.err("Cannot parse unsupported shader resource '{s}'.", .{ @tagName(descriptor.type) });
                    return ShaderError.ResourceNotSupported;
                }
            },
        });

        var populator: ResourceMemberPopulator = .{
            .allocator  = allocator,
            .descriptor = descriptor,
            .layout     = &layout,
            .max_depth  = 32,
        };
        try populator.run();

        try result.shader_layout.resource_layouts.put(try allocator.dupe(u8, descriptor.name), layout);
    }

    return result;
}

const ResourceMemberPopulator = struct {
    allocator: std.mem.Allocator,
    descriptor: *SpirvModule.Descriptor,
    layout: *ResourceLayout,
    max_depth: u32,

    pub fn run(self: *@This()) !void {
        try recursePopulate(
            self,
            &self.descriptor.internal.desc.block,
            null,
            0);
    }

    fn recursePopulate(
        self: *@This(),
        block: *SpirvModule.BlockVariable,
        scope: ?[]const u8,
        depth: i32) !void {

        // Prevent stack abuse.
        if (depth > self.max_depth) {
            log.err("Reached maximum recursion depth!", .{  });
            return ShaderError.ParseFailure;
        }

        // Enumerate each child member from the current block.
        for (0 .. block.member_count) |i| {

            var member = block.members[i];
            const member_name = std.mem.span(member.name);

            // Use the member's name to initialize an empty scope,
            // or, concatenate with the current scope.
            const new_scope = if (scope) |cur_scope| (
                try std.mem.join(self.allocator, ".", &.{ cur_scope, member_name })
            ) else (
                try self.allocator.dupe(u8, member_name)
            );
            defer self.allocator.free(new_scope);

            // Capture member information.
            var info: ResourceLayout.ResourceMemberInfo = .{
                .name = member_name,
                .scope = new_scope,

                .size = .{
                    .actual = member.size,
                    .compact = member.padded_size,
                },

                .stride = .{
                    .relative = member.offset,
                    .absolute = member.absolute_offset,
                },

                .datatype = .{
                    .flags = ResourceLayout.ResourceMemberDatatypeFlags.fromU32(
                        if (member.type_description) |type_desc|
                            type_desc.*.type_flags
                        else
                            0),
                    
                    .numeric = .{
                        .scalar = .{
                            .width = member.numeric.scalar.width,
                            .signedness = member.numeric.scalar.signedness,
                        },
                        .vector = .{
                            .dimensions = member.numeric.vector.component_count,
                        },
                        .matrix = .{
                            .rows = member.numeric.matrix.row_count,
                            .columns = member.numeric.matrix.column_count,
                            .stride = member.numeric.matrix.stride,
                        }
                    },

                    .array = .{
                        .rank = member.array.dims_count,
                        .dimensions = undefined,
                        .stride = member.array.stride,
                    }
                },
            };

            for (0 .. 32) |dim| {
                info.datatype.array.dimensions[dim].size = member.array.dims[dim];
            }

            if (member.member_count > 0) {
                // Recursively process all members with children.
                try recursePopulate(
                    self,
                    &member,
                    new_scope,
                    depth + 1);
            }
            else {
                // This child is a primitive type.
                // Add to the layout.
                try self.layout.addMemberInfo(info);
            }
        }
    }
};

const ResourceParserContext = struct {
    count: u32 = 0,
    binding_counter: u32 = 0,
};

const ShaderParserContext = struct {
    spv_module: *SpirvModule,

    uniform_buffers: ResourceParserContext = .{},
    storage_buffers: ResourceParserContext = .{},
    storage_textures: ResourceParserContext = .{},
    sampled_textures: ResourceParserContext = .{},
    samplers: ResourceParserContext = .{},
};

const ShaderParserResult = struct {
    shader_layout: ShaderLayout,
};