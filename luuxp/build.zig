const std = @import("std");

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const luuxp_module = b.addModule("luuxp", .{
        .root_source_file = b.path("src/root.zig"),
        .target           = target,
        .optimize         = optimize,
    });

    luuxp_module.link_libc = true;

    luuxp_module.addIncludePath(b.path("ext/spirv_reflect"));
    luuxp_module.addCSourceFile(.{
        .file  = b.path("ext/spirv_reflect/spirv_reflect.c"),
        .flags = &[_][]const u8{ "-std=c99" },
    });

    luuxp_module.linkSystemLibrary("SDL3", .{});
    luuxp_module.linkSystemLibrary("physfs", .{});
}