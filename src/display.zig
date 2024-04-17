const SDL = @import("sdl2");
const SCREEN_WIDTH = 64;
const SCREEN_HEIGHT = 32;

pub const Display = struct {
    screen: [SCREEN_HEIGHT][SCREEN_WIDTH]u8 = undefined,
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

    pub fn render(self: *Display) !void {
        mainLoop: while (true) {
            while (SDL.pollEvent()) |ev| {
                switch (ev) {
                    .quit => break :mainLoop,
                    else => {},
                }
            }

            try self.renderer.setColorRGB(0xF7, 0xA4, 0x1D);
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
