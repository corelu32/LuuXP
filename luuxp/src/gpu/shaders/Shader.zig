const std = @import("std");
const root = @import("../../root.zig");
const native = root.native;
const c = native.c;
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
    FeatureNotSupported,
    ParseFailure,
    InitFailure,
};

pub const ShaderLayout = struct {

    allocator: std.mem.Allocator,
    resources: std.StringHashMap(ResourceLayout),

    num_uniform_buffers: u32,
    num_storage_buffers: u32,
    num_storage_textures: u32,
    num_samplers: u32,

    fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .resources = std.StringHashMap(ResourceLayout).init(allocator),

            .num_uniform_buffers = 0,
            .num_storage_buffers = 0,
            .num_storage_textures = 0,
            .num_samplers = 0,
        };
    }

    fn addResourceLayout(self: *@This(), layout: ResourceLayout) !void {
        // Key is based on the resource's name.
        const key = try self.allocator.dupe(u8, layout.info.name);
        try self.resources.put(key, layout);
    }

    fn deinit(self: *@This()) void {
        
        // Deallocate the hash map and its string keys.
        var it = self.resources.iterator();
        while (it.next()) |kvp| {
            self.allocator.free(kvp.key_ptr);
        }

        self.resources.deinit();
    }
};

allocator: std.mem.Allocator,
gpu_device: *GpuDevice,
file_stream: *FileStream,
stage: ShaderStage,
layout: ShaderLayout,
handle: *c.SDL_GPUShader,

pub fn init(allocator: std.mem.Allocator, gpu_device: *GpuDevice, info: InitInfo) !@This() {
    
    var shader: @This() = .{
        .allocator = allocator,
        .gpu_device = gpu_device,
        .file_stream = info.stream,
        .stage = info.stage,
        .layout = undefined,
        .handle = undefined,
    };

    const bytecode = try loadBytecode(allocator, info.stream);
    defer allocator.free(bytecode);

    var spv_module = try SpirvModule.init(allocator, bytecode);
    defer spv_module.deinit();

    // Parse the bytecode, which produces the shader's layout.
    {
        const result = try parseBytecode(allocator, &spv_module, info.stage);
        shader.layout = result.layout;
    }

    // Create the SDL shader object.
    {
        const payload: c.SDL_GPUShaderCreateInfo = .{
            .code       = bytecode.ptr,
            .code_size  = bytecode.len,
            .format     = c.SDL_GPU_SHADERFORMAT_SPIRV,
            .entrypoint = info.entry.ptr,

            .num_uniform_buffers  = shader.layout.num_uniform_buffers,
            .num_storage_buffers  = shader.layout.num_storage_buffers,
            .num_storage_textures = shader.layout.num_storage_textures,
            .num_samplers         = shader.layout.num_samplers,

            .stage = switch (info.stage) {
                .Vertex => c.SDL_GPU_SHADERSTAGE_VERTEX,
                .Fragment => c.SDL_GPU_SHADERSTAGE_FRAGMENT,

                else => {
                    log.err("Shader stage not supported.", .{});
                    return ShaderError.FeatureNotSupported;
                }
            },
        };

        const result = c.SDL_CreateGPUShader(gpu_device.handle, &payload);

        if (result) |r| {
            shader.handle = r;
        }
        else {
            log.err("Failed to create the shader handle. SDL error: {s}", .{ c.SDL_GetError() });
            return ShaderError.InitFailure;
        }
    }

    return shader;
}

pub fn deinit(self: *@This()) void {
    self.layout.deinit();
    c.SDL_ReleaseGPUShader(self.gpu_device.handle, self.handle);
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
        .layout = ShaderLayout.init(allocator),
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
                return ShaderError.FeatureNotSupported;
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
                return ShaderError.FeatureNotSupported;
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
                return ShaderError.FeatureNotSupported;
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
                    return ShaderError.FeatureNotSupported;
                }
            },
        });

        // Recursively populate all member layouts for this resource.
        var populator: ResourceMemberPopulator = .{
            .allocator  = allocator,
            .descriptor = descriptor,
            .layout     = &layout,
            .max_depth  = 32,
        };
        try populator.run();

        // The layout is ready - add to the shader layout.
        try result.layout.addResourceLayout(layout);
    }

    result.layout.num_uniform_buffers = ctx.uniform_buffers.count;
    result.layout.num_storage_buffers = ctx.storage_buffers.count;
    result.layout.num_storage_textures = ctx.storage_textures.count;
    result.layout.num_samplers = ctx.samplers.count;

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
    layout: ShaderLayout,
};