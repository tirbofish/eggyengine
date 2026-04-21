const std = @import("std");
const build_shaders = @import("build-shaders.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add shader compilation step
    const shader_step = build_shaders.addShaderBuildStep(b);

    const eggy = buildEggyLibrary(b, target, optimize);
    buildExecutable(b, target, optimize, eggy, shader_step);
}

// this excludes the actual editor/game attached, only the library itself.
fn buildEggyLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const sdl3 = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
        .c_sdl_preferred_linkage = .static,
    });

    const vulkan = b.dependency("vulkan", .{
        .registry = b.path("deps/vk.xml"),
    }).module("vulkan-zig");

    const logly_dep = b.dependency("logly", .{
        .target = target,
        .optimize = optimize,
    });

    const zigimg_dependency = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });

    const eggy_module = b.createModule(.{
        .root_source_file = b.path("src/engine/eggy.zig"),
        .target = target,
        .optimize = optimize,
    });

    eggy_module.addImport("vulkan", vulkan);
    eggy_module.addImport("sdl3", sdl3.module("sdl3"));
    eggy_module.addImport("logly", logly_dep.module("logly"));
    eggy_module.addImport("zigimg", zigimg_dependency.module("zigimg"));

    return eggy_module;
}

fn buildExecutable(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    eggy: *std.Build.Module,
    shader_step: *std.Build.Step,
) void {
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/game/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    root_module.addImport("eggy", eggy);

    const exe = b.addExecutable(.{
        .name = "eggyengine-demo",
        .root_module = root_module,
    });

    // Shaders should be built before the executable
    exe.step.dependOn(shader_step);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // allows for args like `zig build run -- arg1 arg2 etc`.
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the game");
    run_step.dependOn(&run_cmd.step);
}
