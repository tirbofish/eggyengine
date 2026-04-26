const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- game (executable) ---
    const game = b.dependency("game", .{
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(game.artifact("eggyengine-demo"));

    const run_cmd = b.addRunArtifact(game.artifact("eggyengine-demo"));
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the game");
    run_step.dependOn(&run_cmd.step);

    // --- eggy (library) ---
    const eggy_step = b.step("eggy", "Build the eggy engine library");
    if (b.lazyDependency("eggy", .{
        .target = target,
        .optimize = optimize,
    })) |eggy| {
        _ = eggy;
        eggy_step.dependOn(b.getInstallStep());
    }

    // --- teenygltf (library) ---
    const teenygltf_step = b.step("teenygltf", "Build the teenygltf library");
    if (b.lazyDependency("teenygltf", .{
        .target = target,
        .optimize = optimize,
    })) |teenygltf| {
        teenygltf_step.dependOn(&b.addInstallArtifact(teenygltf.artifact("tinygltf3"), .{}).step);
    }
}