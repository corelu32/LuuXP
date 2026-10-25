const std = @import("std");
const root = @import("../../root.zig");
const GpuDevice = root.GpuDevice;
const Shader = root.Shader;
const c = root.native.c;

const log = std.log.scoped(.GraphicsPipeline);

pub const FillMode = enum { Line, Fill };
pub const CullMode = enum { None, Front, Back };
pub const WindingOrder = enum { Clockwise, CounterClockwise };

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

    fn toSdlObject(self: *@This()) c.SDL_GPURasterizerState {
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

    fn toSdlObject(self: *@This()) c.SDL_GPUMultisampleState {
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

    fn toSdlObject(self: *@This()) c.SDL_GPUDepthStencilState {
        return .{
            // Convert depth test state. If disabled, use INVALID.
            .compare_op = if (self.depth_test) |dt| CompareOperator.toSdlObject(dt.on_compare) else c.SDL_GPU_COMPAREOP_INVALID,

            // Convert front stencil test state. If diabled, use INVALID values.
            .front_stencil_state = if (self.stencil_test) |st| (
                .{
                    .compare_op    = CompareOperator.toSdlObject(st.front.on_compare),
                    .fail_op       = StencilOperator.toSdlObject(st.front.on_stencil_fail),
                    .depth_fail_op = StencilOperator.toSdlObject(st.front.on_depth_fail),
                    .on_pass       = StencilOperator.toSdlObject(st.front.on_pass),
                }
            ) else (
                .{
                    .compare_op    = c.SDL_GPU_COMPAREOP_INVALID,
                    .fail_op       = c.SDL_GPU_STENCILOP_INVALID,
                    .depth_fail_op = c.SDL_GPU_STENCILOP_INVALID,
                    .on_pass       = c.SDL_GPU_STENCILOP_INVALID,
                }
            ),

            // Convert back stencil test state. If disabled, use INVALID values.
            .back_stencil_state = if (self.stencil_test) |st| (
                .{
                    .compare_op    = CompareOperator.toSdlObject(st.back.on_compare),
                    .fail_op       = StencilOperator.toSdlObject(st.back.on_stencil_fail),
                    .depth_fail_op = StencilOperator.toSdlObject(st.back.on_depth_fail),
                    .on_pass       = StencilOperator.toSdlObject(st.back.on_pass),
                }
            ) else (
                .{
                    .compare_op    = c.SDL_GPU_COMPAREOP_INVALID,
                    .fail_op       = c.SDL_GPU_STENCILOP_INVALID,
                    .depth_fail_op = c.SDL_GPU_STENCILOP_INVALID,
                    .on_pass       = c.SDL_GPU_STENCILOP_INVALID,
                }
            ),

            // Convert the compare/write masks.
            .compare_mask = if (self.stencil_test) |st| st.compare_mask else 0,
            .write_mask   = if (self.stencil_test) |st| st.write_mask   else 0,
        };
    }
};

pub const TargetSettings = struct {

};

pub const InitSettings = struct {
    vertex_shader: *Shader,
    fragment_shader: *Shader,
    primitive_type: PrimitiveType,
    rasterizer: RasterizerSettings,
    multisample: MultisampleSettings,
    depth_stencil: ?DepthStencilSettings,
    target: TargetSettings,
};

pub const GraphicsPipelineError = error {
    InitFailure,
};

gpu_device: *GpuDevice,
handle: *c.SDL_GPUGraphicsPipeline,

pub fn init(gpu_device: *GpuDevice, settings: InitSettings) !@This() {

    var pipeline: @This() = .{
        .gpu_device = gpu_device,
        .handle = undefined,
    };

    // Create the pipeline handle.
    {
        const result = c.SDL_CreateGPUGraphicsPipeline(
            gpu_device.handle,
            &.{
                .vertex_shader = settings.vertex_shader.handle,
                .fragment_shader = settings.fragment_shader.handle,

                .primitive_type = switch (settings.primitive_type) {
                    .PointList     => c.SDL_GPU_PRIMITIVETYPE_POINTLIST,
                    .LineList      => c.SDL_GPU_PRIMITIVETYPE_LINELIST,
                    .LineStrip     => c.SDL_GPU_PRIMITIVETYPE_LINESTRIP,
                    .TriangleList  => c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
                    .TriangleStrip => c.SDL_GPU_PRIMITIVETYPE_TRIANGLESTRIP
                },

                .rasterizer_state = settings.rasterizer.toSdlObject(),
                .multisample_state = settings.multisample.toSdlObject(),
                .depth_stencil_state = if (settings.depth_stencil) |ds| ds.toSdlObject() else .{},

                //    TODO: Implement target info.
                //    .target_info = ...
            });
        
        if (result) |r| {
            pipeline.handle = r;
        }
        else {
            log.err("Failed to create the pipeline resource. SDL error: {s}", .{ c.SDL_GetError() });
            return GraphicsPipelineError.InitFailure;
        }
    }

    return pipeline;
}