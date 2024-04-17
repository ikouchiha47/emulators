const std = @import("std");
const SDL = @import("sdl2");

const SCREEN_WIDTH = 64;
const SCREEN_HEIGHT = 32;

pub const Display = struct {
    window: SDL.Window,
    renderer: SDL.Renderer,

    pub fn init() !Display {
        try SDL.init(.{
            .video = true,
            .events = true,
            .audio = true,
        });

        const window = try SDL.createWindow(
            "chipate",
            .{ .centered = {} },
            .{ .centered = {} },
            640,
            320,
            .{ .vis = .shown },
        );

        const renderer = try SDL.createRenderer(window, null, .{ .accelerated = true });

        const display = Display{
            .window = window,
            .renderer = renderer,
        };

        return display;
    }

    pub fn redraw(
        self: *Display,
        screen: *[SCREEN_HEIGHT][SCREEN_WIDTH]u8,
    ) !void {
        // std.debug.print("display screen data {any}", .{screen});

        try self.renderer.setColorRGB(
            0,
            0,
            0,
        );
        try self.renderer.clear();
        try self.renderer.setColorRGB(255, 255, 255);

        for (screen, 0..) |line, y| {
            for (line, 0..) |pixel, x| {
                if (pixel == 1) {
                    try self.renderer.drawPoint(@intCast(x), @intCast(y));
                }
            }
        }
    }

    pub fn render(self: *Display) !void {
        mainLoop: while (true) {
            while (SDL.pollEvent()) |ev| {
                switch (ev) {
                    .quit => break :mainLoop,
                    .key_down => |key| {
                        switch (key.scancode) {
                            .escape => {
                                std.log.info("key pressed: {}\n", .{key.scancode});
                                break :mainLoop;
                            },
                            else => std.log.info("key pressed: {}\n", .{key.scancode}),
                        }
                    },
                    else => {
                        break :mainLoop;
                    },
                }
            }

            try self.renderer.setColorRGB(0, 0, 0);
            try self.renderer.clear();

            self.renderer.present();
        }
    }

    pub fn destroy(self: *Display) void {
        self.renderer.destroy();
        self.window.destroy();
        SDL.quit();
    }
};
