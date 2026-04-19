//! build slang shaders.

const std = @import("std");
const builtin = @import("builtin");

const ShaderEntry = struct {
    name: []const u8,
    entries: []const []const u8,
};

// todo: all of this...just not right. perhaps a manifest, or sweep through dirs?
const shaders = [_]ShaderEntry{
    .{ .name = "shader.slang", .entries = &.{ "vertMain", "fragMain" } },
};

pub fn addShaderBuildStep(b: *std.Build) *std.Build.Step {
    const shader_step = b.step("shaders", "Compile Slang shaders to SPIR-V");

    const slangc_path = findSlangc(b) orelse {
        std.log.err("Could not find slangc. Set VULKAN_SDK or ensure slangc is in PATH.", .{});
        return shader_step;
    };

    const shaders_dir = b.path("src/engine/shaders");
    const output_dir = "zig-out/bin/shaders";

    const mkdir_cmd = b.addSystemCommand(&.{ "mkdir", "-p", output_dir });

    for (shaders) |shader| {
        const compile_cmd = b.addSystemCommand(&.{slangc_path});
        compile_cmd.step.dependOn(&mkdir_cmd.step);

        compile_cmd.addFileArg(shaders_dir.path(b, shader.name));
        compile_cmd.addArgs(&.{
            "-target",              "spirv",
            "-profile",             "spirv_1_4",
            "-emit-spirv-directly", "-fvk-use-entrypoint-name",
        });

        for (shader.entries) |entry| {
            compile_cmd.addArgs(&.{ "-entry", entry });
        }

        const output_name = std.mem.trimRight(u8, shader.name, ".slang");
        compile_cmd.addArg("-o");
        compile_cmd.addArg(b.fmt("{s}/{s}.spv", .{ output_dir, output_name }));

        shader_step.dependOn(&compile_cmd.step);
    }

    return shader_step;
}

fn findSlangc(b: *std.Build) ?[]const u8 {
    // Try VULKAN_SDK environment variable first
    if (std.process.getEnvVarOwned(b.allocator, "VULKAN_SDK")) |sdk_path| {
        const slangc = if (builtin.os.tag == .windows)
            b.fmt("{s}/Bin/slangc.exe", .{sdk_path})
        else
            b.fmt("{s}/x86_64/bin/slangc", .{sdk_path});

        if (std.fs.cwd().access(slangc, .{})) |_| {
            return slangc;
        } else |_| {}
    } else |_| {}

    // Try PATH
    if (std.process.getEnvVarOwned(b.allocator, "PATH")) |path_env| {
        const slangc_name = if (builtin.os.tag == .windows) "slangc.exe" else "slangc";
        var path_iter = std.mem.splitScalar(u8, path_env, if (builtin.os.tag == .windows) ';' else ':');
        while (path_iter.next()) |dir| {
            const slangc = b.fmt("{s}/{s}", .{ dir, slangc_name });
            if (std.fs.cwd().access(slangc, .{})) |_| {
                return slangc;
            } else |_| {}
        }
    } else |_| {}

    return null;
}
