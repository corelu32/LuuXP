const std = @import("std");
const native = @import("native.zig");
const c = native.c;

const log = std.log.scoped(.SpirvContext);

const SpirvError = error {
    InitFailure,
    ConversionError,
    MutationFailure,
};

pub const DescriptorType = enum {
    Sampler,
    CombinedImageSampler,
    SampledImage,
    StorageImage,
    UniformTexelBuffer,
    StorageTexelBuffer,
    UniformBuffer,
    StorageBuffer,
    UniformBufferDynamic,
    StorageBufferDynamic,
    InputAttachment,
    AccelerationStructKHR,

    fn fromNative(id: c.SpvReflectDescriptorType) !@This() {
        return switch (id) {
            c.SPV_REFLECT_DESCRIPTOR_TYPE_SAMPLER                    => .Sampler,
            c.SPV_REFLECT_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER     => .CombinedImageSampler,
            c.SPV_REFLECT_DESCRIPTOR_TYPE_SAMPLED_IMAGE              => .SampledImage,
            c.SPV_REFLECT_DESCRIPTOR_TYPE_STORAGE_IMAGE              => .StorageImage,
            c.SPV_REFLECT_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER       => .UniformTexelBuffer,
            c.SPV_REFLECT_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER       => .StorageTexelBuffer,
            c.SPV_REFLECT_DESCRIPTOR_TYPE_UNIFORM_BUFFER             => .UniformBuffer,
            c.SPV_REFLECT_DESCRIPTOR_TYPE_STORAGE_BUFFER             => .StorageBuffer,
            c.SPV_REFLECT_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC     => .UniformBufferDynamic,
            c.SPV_REFLECT_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC     => .StorageBufferDynamic,
            c.SPV_REFLECT_DESCRIPTOR_TYPE_INPUT_ATTACHMENT           => .InputAttachment,
            c.SPV_REFLECT_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR => .AccelerationStructKHR,

            else => {
                log.err("Invalid SPIR-V reflect descriptor type ID '{}'.", .{ id });
                return SpirvError.ConversionError;
            }
        };
    }
};

pub const Descriptor = struct {

    name: []const u8,
    type: DescriptorType,

    block: struct {
        size: struct {
            compact: u32,
            actual: u32,
        }
    },

    internal: struct {
        mod: *c.SpvReflectShaderModule,
        desc: c.SpvReflectDescriptorBinding,
    },

    fn init(mod: *c.SpvReflectShaderModule, desc: c.SpvReflectDescriptorBinding) !@This() {
        return .{
            .name = std.mem.span(desc.name),
            .type = try DescriptorType.fromNative(desc.descriptor_type),

            .block = .{
                .size = .{
                    .compact = desc.block.size,
                    .actual  = desc.block.padded_size,
                }
            },

            .internal = .{
                .mod = mod,
                .desc = desc,
            },
        };
    }

    pub fn updateBindingNumbers(self: *@This(), space_num: u32, binding_num: u32) !void {
        const result = c.spvReflectChangeDescriptorBindingNumbers(
            self.internal.mod,
            &self.internal.desc,
            binding_num,
            space_num);
        
        if (result != c.SPV_REFLECT_RESULT_SUCCESS) {
            log.err("Failed to mutate shader bytecode's binding numbers.", .{});
            return SpirvError.MutationFailure;
        }
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

        module.descriptors[i] = try Descriptor.init(module.handle, native_desc.*);
    }

    return module;
}

pub fn deinit(self: *@This()) void {
    self.allocator.free(self.descriptors);
    c.spvReflectDestroyShaderModule(self.handle);
    self.allocator.destroy(self.handle);
}