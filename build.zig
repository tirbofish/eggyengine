const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/game/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "eggyengine-demo",
        .root_module = root_module,
    });

    const sdl3 = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
    });

    root_module.addImport("sdl3", sdl3.module("sdl3"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // add args like `zig build run -- arg1 arg2 etc`. 
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the game");
    run_step.dependOn(&run_cmd.step);
}