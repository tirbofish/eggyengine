const std = @import("std");
const sdl = @import("sdl3");

const fps = 60;
const screen = .{
    .width = 800,
    .height = 600,
};

pub fn main() !void {
    defer sdl.shutdown();

    const init_flags = sdl.InitFlags {
        .video = true,
    };
    try sdl.init(init_flags);
    defer sdl.quit(init_flags);

    const window = try sdl.video.Window.init(
        "eggyengine demo", 
        screen.width, 
        screen.height, 
        .{}
    );
    defer window.deinit();

    var fps_capper = sdl.extras.FramerateCapper(f32) {
        .mode = .{
            .limited = fps
        }
    };

    var quit = false;
    while (!quit) {
        const dt = fps_capper.delay();
        _ = dt;

        // Update logic.
        const surface = try window.getSurface();

        // mouse
        const state = sdl.mouse.getState();
        const x = state[1];
        const y = state[2];

        const mid: u8 = @intFromFloat(127.5 + 127.5 * (std.math.sin(x) + std.math.sin(y)) / 2.0);
        try surface.fillRect(null, surface.mapRgb(
            @intFromFloat(@min(255, @max(0, x))),
            mid,
            @intFromFloat(@min(255, @max(0, y))),
        ));

        try window.updateSurface();

        // Event logic.
        while (sdl.events.poll()) |event|
            switch (event) {
                .quit => quit = true,
                .terminating => quit = true,
                else => {},
            };
    }
}