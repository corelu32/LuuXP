const std = @import("std");
const root = @import("../../root.zig");
const Shader = root.Shader;

/// Flags are used to represent type information.
/// Mimics SPIR-V relflect's layout.
pub const ResourceMemberDatatypeFlags = packed struct(u32) {
    is_undefined                         : bool,
    is_void                              : bool,
    is_bool                              : bool,
    is_int                               : bool,
    is_float                             : bool,

    __pad_A__                            : u3,

    is_vector                            : bool,
    is_matrix                            : bool,

    __pad_B__                            : u6,

    is_external_image                    : bool,
    is_external_sampler                  : bool,
    is_external_sampled_image            : bool,
    is_external_block                    : bool,
    is_external_acceleration_structure   : bool,

    __pad_C__                            : u7,

    is_struct                            : bool,
    is_array                             : bool,
    is_ref                               : bool,

    __pad_D__                            : u1,

    pub fn fromU32(flags: u32) @This() {
        return @bitCast(flags);
    }

    pub fn fromCInt(flags: c_int) @This() {
        return @bitCast(@as(u32, @intCast(flags)));
    }
};

/// Provides reflection information for each individual member.
pub const ResourceMemberInfo = struct {
    name: []const u8,
    scope: []const u8,

    size: struct {
        compact: u32,
        actual: u32,
    },

    stride: struct {
        relative: u32,
        absolute: u32,
    },

    datatype: struct {
        flags: ResourceMemberDatatypeFlags,

        /// The member's numeric type information.
        numeric: struct {
            /// Numeric scalar details.
            scalar: struct {
                width: u32,
                signedness: u32,
            },
            /// Vector 
            vector: struct { dimensions: u32 },
            matrix: struct {
                rows: u32,
                columns: u32,
                stride: u32
            }
        },
        /// The member's array type information.
        array: struct {
            /// Number of dimensions.
            rank: u32,
            /// Number of elements per dimension.
            dimensions: [32]struct { size: u32 },
            /// Stride of each element.
            stride: u32,
        },
    },
};

/// High-level information of an entire resource.
pub const ResourceInfo = struct {
    name: []const u8,
    type: Shader.ResourceType,
    stage: Shader.ShaderStage,
    slot: u32,
    space: u32,
    binding: u32,
    size: struct {
        compact: u32,
        actual: u32
    }
};

allocator: std.mem.Allocator,
info: ResourceInfo,
member_map: std.StringHashMap(ResourceMemberInfo),

/// Initialize a resource layout.
pub fn init(allocator: std.mem.Allocator, info: ResourceInfo) !@This() {
    
    // Must duplicate string data to manage ownership.
    var owned_info = info;

    owned_info.name = try allocator.dupe(u8, info.name);
    errdefer allocator.free(owned_info.name);

    return .{
        .info = owned_info,
        .allocator = allocator,
        .member_map = std.StringHashMap(ResourceMemberInfo).init(allocator),
    };
}

/// Add information about one member.
pub fn addMemberInfo(self: *@This(), info: ResourceMemberInfo) !void {
    
    // Must duplicate string data to manage ownership.
    var owned_info = info;

    owned_info.name = try self.allocator.dupe(u8, info.name);
    errdefer self.allocator.free(owned_info.name);

    owned_info.scope = try self.allocator.dupe(u8, info.scope);
    errdefer self.allocator.free(owned_info.scope);
    
    try self.member_map.put(owned_info.scope, owned_info);
}

/// Destroy the resource layout object.
pub fn deinit(self: *@This()) void {
    self.allocator.free(self.info.name);

    // Cleanup member layout objects.
    {
        var iterator = self.member_map.iterator();
        while (iterator.next()) |kvp| {

            // Free each member's 'name' and 'scope' strings.
            self.allocator.free(kvp.value_ptr.name);
            self.allocator.free(kvp.value_ptr.scope);

            // Note: The key uses the same memory as `value_ptr.scope`.
            //       We needn't free it twice!
        }
    }

    self.member_map.deinit();
}