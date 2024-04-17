const std = @import("std");
const SDL = @import("sdl2");

pub const log_level: std.log.Level = .info;

// https://en.wikipedia.org/wiki/CHIP-8
// https://github.com/mattmikolay/chip-8/wiki/Mastering-CHIP‐8
// Chip-8 was capable of accessing 4KB of RAM (4096 Bytes)
// Location (0x000) to (0xFFF) (0 to 4095)
const Memory = struct {
    // 4KB Memory
    memory: [0x1000]u8,

    //Registers in CPU
    v: [16]u8,

    // CHIP-8 allows memory addressing 2^12,
    // so, 16 bits to cover all the address ranges
    ir: u16,
    pc: u16,

    stack: [16]u16,
    sp: u8,

    // Times
    delay_timer: u8,
    sound_timer: u8,

    // Input
    keys: [16]bool,
};

const LoadRomError = error{
    OutOfMemory,
};

// The first 4 bits are used.
const Sprites = [16][5]u8{
    [5]u8{ 0xF0, 0x90, 0x90, 0x90, 0xF0 }, // 0
    [5]u8{ 0x20, 0x60, 0x20, 0x20, 0x70 }, // 1
    [5]u8{ 0xF0, 0x10, 0xF0, 0x80, 0xF0 }, // 2
    [5]u8{ 0xF0, 0x10, 0xF0, 0x10, 0xF0 }, // 3
    [5]u8{ 0x90, 0x90, 0xF0, 0x10, 0x10 }, // 4
    [5]u8{ 0xF0, 0x80, 0xF0, 0x10, 0xF0 }, // 5
    [5]u8{ 0xF0, 0x80, 0xF0, 0x90, 0xF0 }, // 6
    [5]u8{ 0xF0, 0x10, 0x20, 0x40, 0x40 }, // 7
    [5]u8{ 0xF0, 0x90, 0xF0, 0x90, 0xF0 }, // 8
    [5]u8{ 0xF0, 0x90, 0xF0, 0x10, 0x10 }, // 9
    [5]u8{ 0xF0, 0x90, 0xF0, 0x90, 0x90 }, // A
    [5]u8{ 0xE0, 0x90, 0xE0, 0x90, 0xE0 }, // B
    [5]u8{ 0xF0, 0x80, 0xF0, 0x80, 0xF0 }, // C
    [5]u8{ 0xE0, 0x90, 0x90, 0x90, 0xE0 }, // D
    [5]u8{ 0xF0, 0x80, 0xF0, 0x80, 0xF0 }, // E
    [5]u8{ 0xF0, 0x80, 0xF0, 0x80, 0x80 }, // F
};

const EndOfInstruction = error{
    OutOfMemory,
    InvalidInstruction,
};

const Cpu = struct {
    v: [16]u8,

    ir: u16,
    pc: u16,

    pub fn init() Cpu {
        return Cpu{
            .pc = 0x200,
            .v = std.mem.zeroes([16]u8),
            .ir = 0,
        };
    }

    pub fn run(self: *Cpu, memory: [0x1000]u8) !void {
        while (true) {
            try self.execute(memory);
        }

        std.log.info("register state {any}", .{self.v});
        return;
    }

    // Works on a fetch decode execute cycle
    // In case of Chip8 we only need decode and execute
    // Fetch also can be inside this, since its quite simple
    pub fn execute(self: *Cpu, memory: [0x1000]u8) !void {
        if (self.pc + 1 > 0x1000) {
            return EndOfInstruction.OutOfMemory;
        }
        const lo: u8 = memory[self.pc];
        const hi: u8 = memory[self.pc + 1];

        var instruction: u16 = 0;
        instruction = ((instruction | lo) << 8) | hi;

        // std.log.info("read 0x{x} 0x{x:0>2} 0x{x:0>2}", .{ instruction, lo, hi });

        const address = instruction & 0x0FFF;
        const NN: u8 = @intCast(instruction & 0x00FF);
        const N: u4 = @intCast(instruction & 0x000F);
        _ = N;

        // last 4 bits of starting byte
        const x: u4 = @intCast((instruction & 0x0F00) >> 8);

        // first 4 bits of the ending byte
        const y: u4 = @intCast((instruction & 0x00F0) >> 4);
        _ = y;

        try switch ((instruction & 0xF000) >> 12) {
            0x1 => {
                std.log.info("jump", .{});
                self.pc = address;
            },
            0x6 => {
                self.v[x] = NN;
            },
            0xA => {
                self.ir = address;
            },
            else => EndOfInstruction.InvalidInstruction,
        };

        self.pc = self.pc + 2;

        if (lo == 0 and hi == 0) {
            return EndOfInstruction.OutOfMemory;
        }

        return;
    }
};

const Chip8 = struct {
    ram: Memory,
    cpu: Cpu,

    pub fn init() Chip8 {
        const ram = Memory{
            .memory = [_]u8{0} ** 0x1000,
            .v = std.mem.zeroes([16]u8),
            .ir = 0,
            .pc = 0x200,
            .stack = undefined,
            .sp = 0,
            .delay_timer = 0,
            .sound_timer = 0,
            .keys = undefined,
        };

        const cpu = Cpu.init();

        return Chip8{ .ram = ram, .cpu = cpu };
    }

    pub fn load_game(self: *Chip8, gameData: []u8) !void {
        var offset: usize = 0x200;
        const endAddress: usize = offset + gameData.len;

        if (endAddress > self.ram.memory.len) {
            return LoadRomError.OutOfMemory;
        }

        for (0.., gameData) |index, byte| {
            self.ram.memory[offset + index] = byte;
        }

        var i: usize = 0;

        for (Sprites) |sprite| {
            for (sprite) |val| {
                self.ram.memory[i] = val;
                i += 1;
            }
        }

        // std.log.info("memory {any}", .{self.ram.memory});
        // _ = print_memory(self);

        try self.cpu.run(self.ram.memory);
        return;
    }

    pub fn print_memory(self: *Chip8) void {
        for (self.ram.memory) |value| {
            std.debug.print("0x{x:0<2} ", .{value});
        }

        // std.debug.print("\n", .{});
        // std.log.info("gamedata bytearray {any}", .{self.ram.memory});
        //
        return;
    }
};

// Step 1: Read a game file

pub fn readFile(filename: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer file.close();

    const fileSize = (try file.stat()).size;
    std.log.info("fileSize {}\n", .{fileSize});

    const buffer = try file.readToEndAlloc(allocator, fileSize);
    return buffer;
}

pub fn main() !void {
    std.log.info("Hello, world!\n", .{});
    const filename = "./c8games/INVADERS";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const gameData = try readFile(filename, allocator);
    defer allocator.free(gameData);

    // std.log.info("File contents: {any}\n", .{fileContents});

    var chip8 = Chip8.init();
    try chip8.load_game(gameData);

    try SDL.init(.{
        .video = true,
        .events = true,
        .audio = true,
    });
    defer SDL.quit();

    var window = try SDL.createWindow(
        "SDL2 Wrapper Demo",
        .{ .centered = {} },
        .{ .centered = {} },
        640,
        480,
        .{ .vis = .shown },
    );
    defer window.destroy();

    var renderer = try SDL.createRenderer(window, null, .{ .accelerated = true });
    defer renderer.destroy();
    // Display loop

    mainLoop: while (true) {
        while (SDL.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :mainLoop,
                else => {},
            }
        }

        try renderer.setColorRGB(0xF7, 0xA4, 0x1D);
        try renderer.clear();

        renderer.present();
    }
}
