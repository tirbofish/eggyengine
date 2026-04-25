const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
}