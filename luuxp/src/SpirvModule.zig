const std = @import("std");
const native = @import("native.zig");
const c = native.c;

const log = std.log.scoped(.SpirvContext);

const SpirvError = error {
    InitFailure,
};

pub const Descriptor = struct {
    handle: c.SpvReflectDescriptorBinding,

    fn init(obj: c.SpvReflectDescriptorBinding) @This() {
        return .{
            .handle = obj,
        };
    }
};

allocator: std.mem.Allocator,
handle: *c.SpvReflectShaderModule,
descriptors: []Descriptor,

/// Creates the SPIR-V module and enumerates the
/// collection of root-level descriptor objects.
pub fn init(allocator: std.mem.Allocator, bytecode: []u8) !@This() {
    
    var module: @This() = .{
        .handle = undefined,
        .allocator = allocator,
        .descriptors = undefined,
    };

    // Allocate the internal handle.
    module.handle = try allocator.create(c.SpvReflectShaderModule);
    errdefer allocator.destroy(module.handle);

    // Initialize the SPIR-V module.
    {
        const result = c.spvReflectCreateShaderModule(
            bytecode.len,
            bytecode.ptr,
            module.handle);
        
        if (result != c.SPV_REFLECT_RESULT_SUCCESS
        ) {
            log.err("Failed to initialize SPIR-V reflection module.", .{ });
            return SpirvError.InitFailure;
        }
    }
    errdefer c.spvReflectDestroyShaderModule(module.handle);

    var desc_count: u32 = undefined;
    var desc_array: []?*c.SpvReflectDescriptorBinding = undefined;

    // Enumerate the number of root-level descriptors.
    // (Cannot populate descriptors array yet!)
    {
        const result = c.spvReflectEnumerateDescriptorBindings(
            module.handle,
            &desc_count,
            null);
        
        if (result != c.SPV_REFLECT_RESULT_SUCCESS) {
            log.err("Failed to query count of SPIR-V module descriptors.", .{ });
            return SpirvError.InitFailure;
        }
    }
    
    // Allocate the array of descriptors (native-level).
    desc_array = try allocator.alloc(?*c.SpvReflectDescriptorBinding, desc_count);
    defer allocator.free(desc_array);

    // Allocate the array of descriptors (abstraction-level).
    module.descriptors = try allocator.alloc(Descriptor, desc_count);
    errdefer allocator.free(module.descriptors);

    // Rerun the enumerate function to populate the descriptors array.
    {
        const result = c.spvReflectEnumerateDescriptorBindings(
            module.handle,
            &desc_count,
            desc_array.ptr);
        
        if (result != c.SPV_REFLECT_RESULT_SUCCESS) {
            log.err("Failed to populate SPIR-V module descriptors.", .{ });
            return SpirvError.InitFailure;
        }
    }

    // Populate the abstraction-level Descriptor objects.
    for (0 .. desc_count) |i| {
        const native_desc = desc_array[i] orelse {
            log.err("Cannot generate descriptor object using null entry.", .{ });
            return SpirvError.InitFailure;
        };

        module.descriptors[i] = Descriptor.init(native_desc.*);
    }

    return module;
}

pub fn deinit(self: *@This()) void {
    self.allocator.free(self.descriptors);
    c.spvReflectDestroyShaderModule(self.handle);
    self.allocator.destroy(self.handle);
}