const std = @import("std");
const SDL = @import("sdl2");

const SCREEN_WIDTH = 64;
const SCREEN_HEIGHT = 32;

pub const EventKind = enum {
    KeyDown,
    KeyUp,
    Quit,
    None,
};

pub const Event = struct {
    kind: EventKind,
    data: SDL.Scancode,

    pub fn quitEvent() Event {
        return Event{
            .kind = .Quit,
            .data = .escape,
        };
    }

    pub fn noneEvent() Event {
        return Event{
            .kind = .None,
            .data = .escape,
        };
    }

    pub fn keyEvent(event: SDL.Event, key: SDL.Scancode) Event {
        const kind: EventKind = switch (event) {
            .key_up => .KeyUp,
            .key_down => .KeyDown,
            else => .None,
        };
        return Event{
            .kind = kind,
            .data = key,
        };
    }
};

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
            2 * 640,
            2 * 320,
            .{ .vis = .shown },
        );

        const renderer = try SDL.createRenderer(window, null, .{ .accelerated = true });
        try renderer.setLogicalSize(64, 32);

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
        // std.log.info("display screen data {any}", .{screen});

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

        self.renderer.present();
    }

    pub fn clearScreen(self: *Display, screen: *[SCREEN_HEIGHT][SCREEN_WIDTH]u8) void {
        _ = self;

        var y: u8 = 0;
        while (y < SCREEN_HEIGHT) : (y += 1) {
            screen[y] = std.mem.zeroes([SCREEN_WIDTH]u8);
        }
    }

    pub fn getEvent(self: *Display) Event {
        _ = self;

        if (SDL.pollEvent()) |ev| {
            switch (ev) {
                .quit => return Event.quitEvent(),
                .key_down, .key_up => |key| {
                    std.log.debug("key pressed: {}\n", .{key.scancode});

                    switch (key.scancode) {
                        .escape => return Event.quitEvent(),
                        else => return Event.keyEvent(ev, key.scancode),
                    }
                },
                else => {},
            }
        }

        return Event.noneEvent();
    }

    pub fn destroy(self: *Display) void {
        self.renderer.destroy();
        self.window.destroy();
        SDL.quit();
    }
};
