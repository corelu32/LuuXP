const std = @import("std");
const native = @import("native.zig");
const Shader = @import("Shader.zig");

pub const ResourceType = enum {
    UniformBuffer,
    StorageBuffer,
    TexelStorageBuffer,
    SampledImage,
    Sampler,
};

/// Flags are used to represent type information.
/// Mimics SPIR-V relflect's layout.
pub const ResourceMemberTypeInfoFlags = packed struct(u32) {
    is_undefined                         : bool,
    is_void                              : bool,   // 1: 1 << 0 (1)
    is_bool                              : bool,   // 2: 1 << 1 (2)
    is_int                               : bool,   // 3: 1 << 2 (4)
    is_float                             : bool,   // 4: 1 << 3 (8)

    __pad_A__                            : u3,

    is_vector                            : bool,   // 8: 1 << 8 (256)
    is_matrix                            : bool,   // 9: 1 << 9 (512)

    __pad_B__                            : u6,

    is_external_image                    : bool,   // 16: 1 << 16 (65536)
    is_external_sampler                  : bool,   // 17: 1 << 17 (131072)
    is_external_sampled_image            : bool,   // 18: 1 << 18 (262144)
    is_external_block                    : bool,   // 19: 1 << 19 (524288)
    is_external_acceleration_structure   : bool,   // 20: 1 << 20 (1048576)

    __pad_C__                            : u7,

    is_struct                            : bool,   // 28: 1 << 28 (268435456)
    is_array                             : bool,   // 29: 1 << 29 (536870912)
    is_ref                               : bool,   // 30: 1 << 30 (1073741824)

    __pad_D__                            : u1,

    pub fn initFromU32(flags: u32) @This() {
        return @bitCast(flags);
    }

    pub fn initFromCInt(flags: c_int) @This() {
        return @bitCast(@as(u32, @intCast(flags)));
    }
};

/// Holds information about one member of each resource.
pub const ResourceMemberInfo = struct {
    name: []const u8,
    scope: []const u8,

    type_info: struct {
        flags: ResourceMemberTypeInfoFlags,
    },
    size: struct {
        compact: u32,
        actual: u32,
    },
    stride: struct {
        relative: u32,
        absolute: u32,
    },
    numeric: struct {
        scalar: struct {
            width: u32,
            signedness: u32,
        },
        vector: struct { dimensions: u32 },
        matrix: struct {
            rows: u32,
            columns: u32,
            stride: u32
        }
    },
    array: struct {
        dimensions: struct {
            count: u32,
            elements: [32]struct{
                count: u32
            },
        },
        stride: u32,
    },
};

/// High-level information of an entire resource.
pub const ResourceInfo = struct {
    name: []const u8,
    resource_type: ResourceType,
    stage: Shader.ShaderStage,
    slot: u32,
    space: u32,
    binding: u32,
    size: struct {
        compact: u32,
        actual: u32
    },
    count: u32
};

allocator: std.mem.Allocator,
info: ResourceInfo,
members: std.StringHashMap(ResourceMemberInfo),

/// Initialize a resource layout.
pub fn init(allocator: std.mem.Allocator, info: ResourceInfo) @This() {
    return .{
        .info = info,
        .allocator = allocator,
        .members = std.StringHashMap(ResourceMemberInfo).init(allocator),
    };
}

/// Destroy the resource layout object.
pub fn deinit(self: *@This()) void {
    self.members.deinit();
}

/// Add information about one member.
pub fn addMemberInfo(self: *@This(), info: ResourceMemberInfo) !void {
    try self.members.put(info.scope, info);
}