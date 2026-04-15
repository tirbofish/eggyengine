const std = @import("std");
const eggy = @import("eggy");

pub fn main() !void {
    const handle = try eggy.EggyApp.init();
    defer handle.deinit();
}

// fn hello_world_setup(
//     commands: *Commands
// ) !void {

// }
