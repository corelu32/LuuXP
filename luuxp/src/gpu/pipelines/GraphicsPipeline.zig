const std = @import("std");
const root = @import("../../root.zig");
const GpuDevice = root.GpuDevice;
const Shader = root.Shader;
const c = root.native.c;

const log = std.log.scoped(.GraphicsPipeline);

pub const FillMode = enum { Line, Fill };
pub const CullMode = enum { None, Front, Back };
pub const WindingOrder = enum { Clockwise, CounterClockwise };

pub const DepthStencilFormat = enum {
    D16Unorm,
    D24Unorm,
    D32Float,
    D24UnormS8UInt,
    D32FloatS8UInt
};

pub const PrimitiveType = enum {
    PointList,
    LineList,
    LineStrip,
    TriangleList,
    TriangleStrip,
};

pub const CompareOperator = enum {
    Never,
    Equal,
    NotEqual,
    Less,
    Greater,
    LessOrEqual,
    GreaterOrEqual,
    Always,

    fn toSdlObject(op: CompareOperator) c.SDL_GPUCompareOp {
        return switch (op) {
            .Never          => c.SDL_GPU_COMPAREOP_NEVER,
            .Equal          => c.SDL_GPU_COMPAREOP_EQUAL,
            .NotEqual       => c.SDL_GPU_COMPAREOP_NOT_EQUAL,
            .Less           => c.SDL_GPU_COMPAREOP_LESS,
            .Greater        => c.SDL_GPU_COMPAREOP_GREATER,
            .LessOrEqual    => c.SDL_GPU_COMPAREOP_LESS_OR_EQUAL,
            .GreaterOrEqual => c.SDL_GPU_COMPAREOP_GREATER_OR_EQUAL,
            .Always         => c.SDL_GPU_COMPAREOP_ALWAYS,
        };
    }
};

pub const StencilOperator = enum {
    Keep,
    Zero,
    Replace,
    Invert,
    IncrementAndClamp,
    DecrementAndClamp,
    IncrementAndWarp,
    DecrementAndWarp,

    fn toSdlObject(op: StencilOperator) c.SDL_GPUStencilOp {
        return switch (op) {
            .Keep              => c.SDL_GPU_STENCILOP_KEEP,
            .Zero              => c.SDL_GPU_STENCILOP_ZERO,
            .Replace           => c.SDL_GPU_STENCILOP_REPLACE,
            .Invert            => c.SDL_GPU_STENCILOP_INVERT,
            .IncrementAndClamp => c.SDL_GPU_STENCILOP_INCREMENT_AND_CLAMP,
            .DecrementAndClamp => c.SDL_GPU_STENCILOP_DECREMENT_AND_CLAMP,
            .IncrementAndWarp  => c.SDL_GPU_STENCILOP_INCREMENT_AND_WRAP,
            .DecrementAndWarp  => c.SDL_GPU_STENCILOP_DECREMENT_AND_WRAP,
        };
    }
};

pub const ColorTargetBlendFactor = enum {
    Zero,
    One,
    SourceColor,
    OneMinusSourceColor,
    DestColor,
    OneMinusDestColor,
    SourceAlpha,
    OneMinusSourceAlpha,
    DestAlpha,
    OneMinusDestAlpha,
    ConstantColor,
    OneMinusConstColor,
    SourceAlphaSaturate,

    fn toSdlObject(self: @This()) c.SDL_BlendFactor {
        return switch(self) {
            .Zero                => c.SDL_GPU_BLENDFACTOR_ZERO,
            .One                 => c.SDL_GPU_BLENDFACTOR_ONE,
            .SourceColor         => c.SDL_GPU_BLENDFACTOR_SRC_COLOR,
            .OneMinusSourceColor => c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_COLOR,
            .DestColor           => c.SDL_GPU_BLENDFACTOR_DST_COLOR,
            .OneMinusDestColor   => c.SDL_GPU_BLENDFACTOR_ONE_MINUS_DST_COLOR,
            .SourceAlpha         => c.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
            .OneMinusSourceAlpha => c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            .DestAlpha           => c.SDL_GPU_BLENDFACTOR_DST_ALPHA,
            .OneMinusDestAlpha   => c.SDL_GPU_BLENDFACTOR_ONE_MINUS_DST_ALPHA,
            .ConstantColor       => c.SDL_GPU_BLENDFACTOR_CONSTANT_COLOR,
            .OneMinusConstColor  => c.SDL_GPU_BLENDFACTOR_ONE_MINUS_CONSTANT_COLOR,
            .SourceAlphaSaturate => c.SDL_GPU_BLENDFACTOR_SRC_ALPHA_SATURATE,
        };
    }
};

pub const ColorComponentFlags = packed struct(u4) {
    Red   : bool = false,
    Green : bool = false,
    Blue  : bool = false,
    Alpha : bool = false,
};

pub const ColorTargetBlendOperator = enum {
    Add,
    Subtract,
    SubtractReverse,
    Min,
    Max,

    fn toSdlObject(self: ColorTargetBlendOperator) c.SDL_BlendOperation {
        return switch (self) {
            .Add             => c.SDL_BLENDOPERATION_ADD,
            .Subtract        => c.SDL_BLENDOPERATION_SUBTRACT,
            .SubtractReverse => c.SDL_BLENDOPERATION_REV_SUBTRACT,
            .Min             => c.SDL_BLENDOPERATION_MINIMUM,
            .Max             => c.SDL_BLENDOPERATION_MAXIMUM,
        };
    }
};

pub const ColorTargetTextureFormat = union(enum) {
    UNorm     : enum { R8,    Rgba8,  Bgra8,                          },
    Float     : enum { R16,   Rg16,   Rgba16,  R32,   Rg32,   Rgba32, },
    Uint      : enum { R8,    Rg8,    Rgba8,   R16,   Rg16,   Rgba16, },
    Int       : enum { R8,    Rg8,    Rgba8,   R16,   Rg16,   Rgba16  },
    UNormSrgb : enum { Rgba8, Bgra8                                   },

    fn toSdlObject(self: ColorTargetTextureFormat) c.SDL_GPUTextureFormat {
        return switch (self) {
            .UNorm => |sub| switch (sub) {
                .R8    => c.SDL_GPU_TEXTUREFORMAT_R8_UNORM,
                .Rgba8 => c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
                .Bgra8 => c.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM,
            },
            .Float => |sub| switch (sub) {
                .R16    => c.SDL_GPU_TEXTUREFORMAT_R16_FLOAT,
                .Rg16   => c.SDL_GPU_TEXTUREFORMAT_R16G16_FLOAT,
                .Rgba16 => c.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT,
                .R32    => c.SDL_GPU_TEXTUREFORMAT_R32_FLOAT,
                .Rg32   => c.SDL_GPU_TEXTUREFORMAT_R32G32_FLOAT,
                .Rgba32 => c.SDL_GPU_TEXTUREFORMAT_R32G32B32A32_FLOAT,
            },
            .Uint => |sub| switch (sub) {
                .R8     => c.SDL_GPU_TEXTUREFORMAT_R8_UINT,
                .Rg8    => c.SDL_GPU_TEXTUREFORMAT_R8G8_UINT,
                .Rgba8  => c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UINT,
                .R16    => c.SDL_GPU_TEXTUREFORMAT_R16_UINT,
                .Rg16   => c.SDL_GPU_TEXTUREFORMAT_R16G16_UINT,
                .Rgba16 => c.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_UINT,
            },
            .Int => |sub| switch (sub) {
                .R8     => c.SDL_GPU_TEXTUREFORMAT_R8_INT,
                .Rg8    => c.SDL_GPU_TEXTUREFORMAT_R8G8_INT,
                .Rgba8  => c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_INT,
                .R16    => c.SDL_GPU_TEXTUREFORMAT_R16_INT,
                .Rg16   => c.SDL_GPU_TEXTUREFORMAT_R16G16_INT,
                .Rgba16 => c.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_INT,
            },
            .UNormSrgb => |sub| switch (sub) {
                .Rgba8 => c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB,
                .Bgra8 => c.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM_SRGB,
            },
        };
    }
};

pub const ColorTarget = struct {
    format: ColorTargetTextureFormat,

    blending: ?struct {
        color: struct {
            source_factor: ColorTargetBlendFactor,
            dest_factor: ColorTargetBlendFactor,
            on_blend: ColorTargetBlendOperator,
        },

        alpha: struct {
            source_factor: ColorTargetBlendFactor,
            dest_factor: ColorTargetBlendFactor,
            on_blend: ColorTargetBlendOperator,
        },
    },

    color_write_mask: ?ColorComponentFlags,

    fn toSdlObject(self: *const @This()) c.SDL_GPUColorTargetDescription {
        return .{
            .format = self.format.toSdlObject(),
            .blend_state = .{
                .src_color_blendfactor = if (self.blending) |b| b.color.source_factor.toSdlObject() else undefined,
                .dst_color_blendfactor = if (self.blending) |b| b.color.dest_factor.toSdlObject()   else undefined,
                .color_blend_op        = if (self.blending) |b| b.color.on_blend.toSdlObject()      else undefined,

                .src_alpha_blendfactor = if (self.blending) |b| b.alpha.source_factor.toSdlObject() else undefined,
                .dst_alpha_blendfactor = if (self.blending) |b| b.alpha.dest_factor.toSdlObject()   else undefined,
                .alpha_blend_op        = if (self.blending) |b| b.alpha.on_blend.toSdlObject()      else undefined,

                .color_write_mask        = if (self.color_write_mask) |v| @as(u4, @bitCast(v)) else 0,
                .enable_color_write_mask = self.color_write_mask != null,
            },
        };
    }
};

pub const RasterizerSettings = struct {
    fill_mode: FillMode,
    cull_mode: CullMode,
    winding_order: WindingOrder,

    depth_bias: ?struct {
        constant_factor: f32,
        slope_factor: f32,
        clamp: f32,
    },

    enable_depth_clip: bool,

    fn toSdlObject(self: *const @This()) c.SDL_GPURasterizerState {
        return .{
            .fill_mode = switch (self.fill_mode) {
                .Line => c.SDL_GPU_FILLMODE_LINE,
                .Fill => c.SDL_GPU_FILLMODE_FILL,
            },

            .cull_mode = switch (self.cull_mode) {
                .None  => c.SDL_GPU_CULLMODE_NONE,
                .Front => c.SDL_GPU_CULLMODE_FRONT,
                .Back  => c.SDL_GPU_CULLMODE_BACK,
            },

            .front_face = switch (self.winding_order) {
                .Clockwise => c.SDL_GPU_FRONTFACE_CLOCKWISE,
                .CounterClockwise => c.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
            },

            .depth_bias_constant_factor = if (self.depth_bias) |db| db.constant_factor else 0.0,
            .depth_bias_slope_factor    = if (self.depth_bias) |db| db.slope_factor else 0.0,
            .depth_bias_clamp           = if (self.depth_bias) |db| db.clamp else 0.0,
            
            .enable_depth_bias = self.depth_bias != null,
            .enable_depth_clip = self.enable_depth_clip,
        };
    }
};

pub const MultisampleSettings = struct {
    sample_count: u8,
    enable_alpha_to_coverage: bool,

    fn toSdlObject(self: *const @This()) !c.SDL_GPUMultisampleState {
        return .{
            .sample_count = switch (self.sample_count) {
                1 => c.SDL_GPU_SAMPLECOUNT_1,
                2 => c.SDL_GPU_SAMPLECOUNT_2,
                4 => c.SDL_GPU_SAMPLECOUNT_4,
                8 => c.SDL_GPU_SAMPLECOUNT_8,

                else => {
                    log.err("Invalid sample count provided.", .{ });
                    return GraphicsPipelineError.InitFailure;
                }
            },

            .enable_alpha_to_coverage = self.enable_alpha_to_coverage,

            .sample_mask = 0,     // "Reserved for future use. Must be set to 0."
            .enable_mask = false, // "Reserved for future use. Must be set to false."
        };
    }
};

pub const DepthStencilSettings = struct {
    stencil_test: ?struct {
        front: struct {
            on_compare: CompareOperator,
            on_stencil_fail: StencilOperator,
            on_depth_fail: StencilOperator,
            on_pass: StencilOperator,
        },

        back: struct {
            on_compare: CompareOperator,
            on_stencil_fail: StencilOperator,
            on_depth_fail: StencilOperator,
            on_pass: StencilOperator,
        },

        compare_mask: u8,
        write_mask: u8
    },

    depth_test: ?struct {
        on_compare: CompareOperator,
        enable_writes: bool,
    },

    fn toSdlObject(self: *const @This()) c.SDL_GPUDepthStencilState {
        return .{
            // Convert depth test state. If disabled, use INVALID.
            .compare_op = if (self.depth_test) |dt| CompareOperator.toSdlObject(dt.on_compare) else c.SDL_GPU_COMPAREOP_INVALID,

            // Convert front stencil test state. If diabled, use INVALID values.
            .front_stencil_state = if (self.stencil_test) |st| (
                .{
                    .compare_op    = CompareOperator.toSdlObject(st.front.on_compare),
                    .fail_op       = StencilOperator.toSdlObject(st.front.on_stencil_fail),
                    .depth_fail_op = StencilOperator.toSdlObject(st.front.on_depth_fail),
                    .pass_op       = StencilOperator.toSdlObject(st.front.on_pass),
                }
            ) else (
                .{
                    .compare_op    = c.SDL_GPU_COMPAREOP_INVALID,
                    .fail_op       = c.SDL_GPU_STENCILOP_INVALID,
                    .depth_fail_op = c.SDL_GPU_STENCILOP_INVALID,
                    .pass_op       = c.SDL_GPU_STENCILOP_INVALID,
                }
            ),

            // Convert back stencil test state. If disabled, use INVALID values.
            .back_stencil_state = if (self.stencil_test) |st| (
                .{
                    .compare_op    = CompareOperator.toSdlObject(st.back.on_compare),
                    .fail_op       = StencilOperator.toSdlObject(st.back.on_stencil_fail),
                    .depth_fail_op = StencilOperator.toSdlObject(st.back.on_depth_fail),
                    .pass_op       = StencilOperator.toSdlObject(st.back.on_pass),
                }
            ) else (
                .{
                    .compare_op    = c.SDL_GPU_COMPAREOP_INVALID,
                    .fail_op       = c.SDL_GPU_STENCILOP_INVALID,
                    .depth_fail_op = c.SDL_GPU_STENCILOP_INVALID,
                    .pass_op       = c.SDL_GPU_STENCILOP_INVALID,
                }
            ),

            // Convert the compare/write masks.
            .compare_mask = if (self.stencil_test) |st| st.compare_mask else 0,
            .write_mask   = if (self.stencil_test) |st| st.write_mask   else 0,
        };
    }
};

pub const InitSettings = struct {
    vertex_shader: *Shader,
    fragment_shader: *Shader,
    primitive_type: PrimitiveType,
    rasterizer: RasterizerSettings,
    multisample: MultisampleSettings,
    depth_stencil: ?DepthStencilSettings,
    color_targets: []const ColorTarget,
};

pub const GraphicsPipelineError = error {
    InitFailure,
};

allocator: std.mem.Allocator,
gpu_device: *GpuDevice,
handle: *c.SDL_GPUGraphicsPipeline,

pub fn init(allocator: std.mem.Allocator, gpu_device: *GpuDevice, settings: InitSettings) !@This() {

    var pipeline: @This() = .{
        .allocator = allocator,
        .gpu_device = gpu_device,
        .handle = undefined,
    };

    const has_depth_stencil_target = settings.depth_stencil != null;

    // Invalid format by default...
    var depth_stencil_format = c.SDL_GPU_TEXTUREFORMAT_INVALID;

    // Automatically select the best depth-stencil texture format,
    // based on GPU specs, and whether the stencil-test is enabled or not.
    // (ONLY IF THERE IS A DEPTH STENCIL TARGET!)
    if (has_depth_stencil_target)
    {
        // Check if the stencil-test is enabled.
        const depth_and_stencil = if (settings.depth_stencil) |ds| (
            ds.stencil_test == null
        ) else false;

        if (depth_and_stencil) {
            // Use these texture formats for depth/stencil tests.
            // Use the highest quality format available.

            const HIGH_QUALITY_FORMAT = c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT; // 32-bit high-end format.
            const DEFAULT_FORMAT      = c.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT; // 24-bit standard format.

            const use_high_quality = c.SDL_GPUTextureSupportsFormat(
                gpu_device.handle,
                HIGH_QUALITY_FORMAT,
                c.SDL_GPU_TEXTURETYPE_2D,
                c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET);

            depth_stencil_format = if (use_high_quality) HIGH_QUALITY_FORMAT else DEFAULT_FORMAT;
        }
        else {
            // Use these texture formats for depth-only tests.
            // Use the highest quality format available.

            const HIGH_QUALITY_FORMAT = c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT; // 32-bit high-end format.
            const DEFAULT_FORMAT      = c.SDL_GPU_TEXTUREFORMAT_D16_UNORM; // 16-bit legacy format.

            const use_high_quality = c.SDL_GPUTextureSupportsFormat(
                gpu_device.handle,
                HIGH_QUALITY_FORMAT,
                c.SDL_GPU_TEXTURETYPE_2D,
                c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET);

            depth_stencil_format = if (use_high_quality) HIGH_QUALITY_FORMAT else DEFAULT_FORMAT;
        }
    }

    // Allocate array of native color targets.
    var sdl_color_targets = try allocator.alloc(c.SDL_GPUColorTargetDescription, settings.color_targets.len);
    defer allocator.free(sdl_color_targets);

    // Convert each color target to the SDL-native object.
    for (0 .. sdl_color_targets.len) |i| {
        sdl_color_targets[i] = settings.color_targets[i].toSdlObject();
    }

    // Build SDL's target_info object.
    const target_info: c.SDL_GPUGraphicsPipelineTargetInfo = .{
        .color_target_descriptions = sdl_color_targets.ptr,
        .num_color_targets         = @intCast(sdl_color_targets.len),
        .depth_stencil_format      = @intCast(depth_stencil_format),
        .has_depth_stencil_target  = has_depth_stencil_target,
    };

    // Create the pipeline handle.
    {
        const payload: c.SDL_GPUGraphicsPipelineCreateInfo = .{
            .vertex_shader = settings.vertex_shader.handle,
            .fragment_shader = settings.fragment_shader.handle,

            .primitive_type = switch (settings.primitive_type) {
                .PointList     => c.SDL_GPU_PRIMITIVETYPE_POINTLIST,
                .LineList      => c.SDL_GPU_PRIMITIVETYPE_LINELIST,
                .LineStrip     => c.SDL_GPU_PRIMITIVETYPE_LINESTRIP,
                .TriangleList  => c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
                .TriangleStrip => c.SDL_GPU_PRIMITIVETYPE_TRIANGLESTRIP
            },

            .target_info         = target_info,
            .rasterizer_state    = settings.rasterizer.toSdlObject(),
            .multisample_state   = try settings.multisample.toSdlObject(),
            .depth_stencil_state = if (settings.depth_stencil) |ds|
                                        ds.toSdlObject() else .{},
        };

        const result = c.SDL_CreateGPUGraphicsPipeline(gpu_device.handle, &payload);
        
        if (result) |r| {
            // Handle creation succeeded!
            // Set the handle.
            pipeline.handle = r;
        }
        else {
            log.err("Failed to create the pipeline resource. SDL error: {s}", .{ c.SDL_GetError() });
            return GraphicsPipelineError.InitFailure;
        }
    }

    return pipeline;
}