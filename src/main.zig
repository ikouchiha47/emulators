const std = @import("std");
const fb = @import("display.zig");

const SCREEN_WIDTH = 64;
const SCREEN_HEIGHT = 32;

pub const log_level: std.log.Level = .info;

// https://en.wikipedia.org/wiki/CHIP-8
// https://github.com/mattmikolay/chip-8/wiki/Mastering-CHIP‐8
// https://jackson-s.me/2019/07/13/Chip-8-Instruction-Scheduling-and-Frequency.html
// Chip-8 was capable of accessing 4KB of RAM (4096 Bytes)
// Location (0x000) to (0xFFF) (0 to 4095)
const Memory = struct {
    // 4KB Memory
    memory: [0x1000]u8,

    //Registers in CPU
    // v: [16]u8,

    // CHIP-8 allows memory addressing 2^12,
    // so, 16 bits to cover all the address ranges
    // ir: u16,
    pc: u16,

    // stack: [16]u16,
    // sp: u8,

    // Times
    delay_timer: u8,
    sound_timer: u8,

    // Input
    keys: [16]bool,

    pub fn init() Memory {
        return Memory{
            .memory = [_]u8{0} ** 0x1000,
            .pc = 0x200,
            .delay_timer = 0,
            .sound_timer = 0,
            .keys = undefined,
        };
    }
};

const LoadRomError = error{
    OutOfMemory,
};

// The first 4 bits are used.
const Sprites = [80]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0x10, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

const ExecutionError = error{
    OutOfMemory,
    InvalidInstruction,
    UnknownInstruction,
};

const Cpu = struct {
    rnd: std.rand.Xoshiro256,

    v: [16]u8,
    ir: u16,
    pc: u16,

    stack: [16]u16,
    sp: u8,

    display: fb.Display,
    screen: [SCREEN_HEIGHT][SCREEN_WIDTH]u8,

    pub fn init() !Cpu {
        const display = try fb.Display.init();

        return Cpu{
            .pc = 0x200,
            .v = std.mem.zeroes([16]u8),
            .ir = 0,
            .sp = 0,
            .stack = std.mem.zeroes([16]u16),
            .display = display,
            .screen = std.mem.zeroes([SCREEN_HEIGHT][SCREEN_WIDTH]u8),
            .rnd = std.rand.DefaultPrng.init(0),
        };
    }

    pub fn run(self: *Cpu, memory: [0x1000]u8) !void {
        var runLen: i32 = 400;

        while (runLen > 0) {
            try self.execute(memory);
            try self.display.redraw(&self.screen);

            std.time.sleep(16 * 1000 * 1000);
            runLen -= 1;
        }

        std.log.info("register state {any}", .{self.v});
        return;
    }

    pub fn doMath(self: *Cpu, op: u4, x: u4, y: u4) !void {
        try switch (op) {
            0 => self.v[x] = self.v[y],
            else => ExecutionError.UnknownInstruction,
        };
    }

    // Works on a fetch decode execute cycle
    // In case of Chip8 we only need decode and execute
    // Fetch also can be inside this, since its quite simple
    pub fn execute(self: *Cpu, memory: [0x1000]u8) !void {
        if (self.pc + 1 > 0x1000) {
            return ExecutionError.OutOfMemory;
        }

        const lo: u8 = memory[self.pc];
        const hi: u8 = memory[self.pc + 1];

        const prev_pc = self.pc;
        _ = prev_pc;

        std.log.info("\npc: 0x{x:0>4}, pc+1: 0x{x:0>4}", .{ self.pc, self.pc + 1 });
        self.pc += 2;

        var instruction: u16 = 0;
        instruction = ((instruction | lo) << 8) | hi;

        std.log.info("read inst: 0x{x} lo: 0x{x:0>2} hi: 0x{x:0>2} pc: 0x{x:0>4}", .{ instruction, lo, hi, self.pc });

        const address: u16 = instruction & 0x0FFF;
        const nn: u8 = @intCast(instruction & 0x00FF);
        const n: u4 = @intCast(instruction & 0x000F);

        // std.log.info("address 0x{x}", .{address});
        // last 4 bits of starting byte
        const x: u4 = @intCast((instruction & 0x0F00) >> 8);

        // first 4 bits of the ending byte
        const y: u4 = @intCast((instruction & 0x00F0) >> 4);

        // std.log.info("instruction 0x{x} 0x{x:0<2}", .{ instruction, (instruction & 0xf000) >> 12 });

        try switch ((instruction & 0xF000) >> 12) {
            0x0 => {
                if (nn == 0xe0) {
                    self.clearScreen();
                } else if (nn == 0xee) {
                    self.sp -= 1;
                    self.pc = self.stack[self.sp];
                }
            },
            0x1 => {
                std.log.info("jump 0x{x:0>2}", .{address});
                if (address > 0x1000) {
                    return ExecutionError.OutOfMemory;
                }
                self.pc = address;
            },
            0x2 => {
                std.log.info("call subroutine", .{});
                self.stack[self.sp] = self.pc;
                self.sp += 1;
                self.pc = address;
            },
            0x3 => {
                if (self.v[x] == nn) {
                    self.pc += 2;
                }
            },
            0x4 => {
                if (self.v[x] != nn) {
                    self.pc += 2;
                }
            },
            0x5 => {
                if (self.v[x] == self.v[y]) {
                    self.pc += 2;
                }
            },
            0x6 => {
                self.v[x] = nn;
            },
            0x7 => {
                const res = @addWithOverflow(self.v[x], nn);
                self.v[x] = res[0];
            },
            0x8 => {
                try self.doMath(n, x, y);
            },
            0x9 => {
                if (self.v[x] != self.v[y]) {
                    self.pc += 2;
                }
            },
            0xA => {
                self.ir = address;
            },
            0xB => {
                self.pc = address + self.v[0];
            },
            0xC => {
                std.log.info("set vx to rand() & nn", .{});
                const randnum: u8 = self.rnd.random().int(u8);

                self.v[x] = randnum & nn;
            },
            0xD => {
                const vx = self.v[x] & 63; // clamp the value to screen width
                const vy = self.v[y] & 31; // clamp the value to screen height
                const height = n;

                try self.draw(memory, vx, vy, height);
            },
            0xE => {
                std.log.info("skipping 0xE for now", .{});
            },
            0xF => {
                std.log.info("skipping 0xF for now", .{});
            },
            else => ExecutionError.InvalidInstruction,
        };

        std.log.info("register state {any}", .{self.v});

        if (lo == 0 and hi == 0) {
            return ExecutionError.OutOfMemory;
        }

        return;
    }

    fn clearScreen(self: *Cpu) void {
        var y: u8 = 0;
        while (y < SCREEN_HEIGHT) : (y += 1) {
            self.screen[y] = std.mem.zeroes([SCREEN_WIDTH]u8);
        }
    }

    fn draw(self: *Cpu, mem: [0x1000]u8, vx: u8, vy: u8, height: u4) !void {
        self.v[0xf] = 0;

        var n: u4 = 0;
        var y: u8 = vy;

        while (n < height) : (n += 1) {
            var x: u8 = vx;
            var sprite: u8 = mem[self.ir + n];
            var bit: u8 = 0;

            while (bit < 8) : (bit += 1) {
                if ((sprite & 0x80) == 0x80) { //0x80 = 10000000. give the LSB and matches to be 1
                    if (self.screen[y][x] == 1) {
                        // turn off and set vf = 1
                        self.screen[y][x] = 0;
                        self.v[0xf] = 1;
                    } else {
                        self.screen[y][x] = 1;
                    }
                }

                sprite = sprite << 1;
                x += 1;

                if (x == 64) break;
            }

            y += 1;
            if (y == 32) break;
        }

        // std.log.info("lalalala {any}", .{self.screen});
    }
};

const Chip8 = struct {
    ram: Memory,
    cpu: Cpu,

    pub fn init() !Chip8 {
        const ram = Memory.init();
        const cpu = try Cpu.init();

        return Chip8{
            .ram = ram,
            .cpu = cpu,
        };
    }

    pub fn load_game(self: *Chip8, gameData: []u8) !void {
        const offset: usize = 0x200;
        const endAddress: usize = offset + gameData.len;

        if (endAddress > self.ram.memory.len) {
            return LoadRomError.OutOfMemory;
        }

        @memcpy(self.ram.memory[0..80], Sprites[0..80]);

        for (0.., gameData) |index, byte| {
            self.ram.memory[offset + index] = byte;
        }

        _ = self.print_memory(gameData);

        std.debug.print("{any}\n", .{gameData});

        try self.cpu.run(self.ram.memory);
        return;
    }

    pub fn print_memory(self: *Chip8, gameData: []u8) void {
        _ = self;
        for (gameData) |value| {
            std.debug.print("0x{x:0>2} ", .{value});
        }

        // for (self.ram.memory) |value| {
        //     std.debug.print("0x{x:0<2} ", .{value});
        // }

        std.debug.print("\n", .{});
        // std.log.info("gamedata bytearray {any}", .{self.ram.memory});
        //
        return;
    }
};

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
    const filename = "./c8games/IBMLOGO";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const gameData = try readFile(filename, allocator);
    defer allocator.free(gameData);

    // std.log.info("File contents: {any}\n", .{fileContents});

    var chip8 = try Chip8.init();
    try chip8.load_game(gameData);

    // Display loop
    var display = try fb.Display.init();
    defer display.destroy();

    try display.render();
}
