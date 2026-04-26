const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tinygltf3_dep = b.dependency("tinygltf3", .{});

    const lib = b.addLibrary(.{
        .name = "tinygltf3",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });

    const wf = b.addWriteFiles();
    const impl_file = wf.add("tinygltf3_impl.cpp",
        \\#define TINYGLTF3_IMPLEMENTATION
        \\#include "tiny_gltf_v3.h"
    );

    lib.root_module.addCSourceFile(.{
        .file = impl_file,
        .flags = &.{},
    });
    lib.root_module.addIncludePath(tinygltf3_dep.path(""));

    const mod = b.addModule("teenygltf", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addIncludePath(tinygltf3_dep.path(""));
    mod.linkLibrary(lib);

    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.root_module.addIncludePath(tinygltf3_dep.path(""));
    tests.root_module.linkLibrary(lib);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run teenygltf tests");
    test_step.dependOn(&run_tests.step);
}