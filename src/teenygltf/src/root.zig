pub const c = @cImport({
    @cInclude("tiny_gltf_v3.h");
});

const std = @import("std");
const testing = std.testing;

pub const Model = c.tg3_model;
pub const ErrorStack = c.tg3_error_stack;
pub const ErrorCode = c.tg3_error_code;
pub const ParseOptions = c.tg3_parse_options;
pub const WriteOptions = c.tg3_write_options;

pub fn parseOptionsInit() ParseOptions {
    var opts: ParseOptions = undefined;
    c.tg3_parse_options_init(&opts);
    return opts;
}

pub fn errorStackInit() ErrorStack {
    var es: ErrorStack = undefined;
    c.tg3_error_stack_init(&es);
    return es;
}

pub fn parseAuto(
    data: []const u8,
    base_dir: ?[]const u8,
    options: ?*const ParseOptions,
) struct { model: Model, errors: ErrorStack } {
    var model: Model = undefined;
    var errors = errorStackInit();
    var opts = parseOptionsInit();

    const dir_ptr = if (base_dir) |d| d.ptr else null;
    const dir_len: u32 = if (base_dir) |d| @intCast(d.len) else 0;
    const opt_ptr = options orelse &opts;

    _ = c.tg3_parse_auto(
        &model, &errors,
        data.ptr, data.len,
        dir_ptr, dir_len,
        opt_ptr,
    );

    return .{ .model = model, .errors = errors };
}

pub fn modelFree(model: *Model) void {
    c.tg3_model_free(model);
}

pub fn errorStackFree(es: *ErrorStack) void {
    c.tg3_error_stack_free(es);
}

test "parse options init has sensible defaults" {
    const opts = parseOptionsInit();
    try testing.expectEqual(@as(c_uint, 0), opts.strictness);
}

test "error stack init is empty" {
    var es = errorStackInit();
    defer errorStackFree(&es);
    try testing.expectEqual(@as(u32, 0), es.count);
    try testing.expectEqual(@as(i32, 0), es.has_error);
}

test "model free on zeroed model does not crash" {
    var model: Model = std.mem.zeroes(Model);
    modelFree(&model);
}

test "parse empty json reports error" {
    const result = parseAuto(&.{}, null, null);
    var model = result.model;
    var errors = result.errors;
    defer modelFree(&model);
    defer errorStackFree(&errors);
    // Empty input should produce an error
    try testing.expect(errors.has_error != 0);
}

test "parse minimal valid gltf" {
    const minimal_gltf =
        \\{"asset":{"version":"2.0"}}
    ;
    const result = parseAuto(minimal_gltf, null, null);
    var model = result.model;
    var errors = result.errors;
    defer modelFree(&model);
    defer errorStackFree(&errors);

    try testing.expectEqual(@as(i32, 0), errors.has_error);
}