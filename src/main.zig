const std = @import("std");
const times = @import("times.zig");
const SDL = @import("sdl2");

const fb = @import("display.zig");

const SCREEN_WIDTH = 64;
const SCREEN_HEIGHT = 32;
const TIME_MULT = 1000;

pub const std_options = .{ .log_level = .info };

// Chip-8 was capable of accessing 4KB of RAM (4096 Bytes)
// Location (0x000) to (0xFFF) (0 to 4095)
const Memory = struct {
    // 4KB Memory
    memory: [0x0fff]u8,

    // CHIP-8 allows memory addressing 2^12,
    // so, 16 bits to cover all the address ranges
    // ir: u16,
    pc: u16,

    pub fn init() Memory {
        return Memory{
            .memory = [_]u8{0} ** 0x1000,
            .pc = 0x200,
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
    UnregisteredKey,
};

fn print_memory(gameData: []u8) void {
    for (gameData) |value| {
        std.debug.print("0x{x:0>2} ", .{value});
    }

    std.debug.print("\n", .{});
    return;
}

const CpuState = enum {
    Running,
    IOWaiting,
};

const Cpu = struct {
    rnd: std.rand.Xoshiro256,

    v: [16]u8,
    ir: u16,
    pc: u16,

    stack: [64]u16,
    sp: u8,

    delay_timer: u8,
    sound_timer: u8,

    // Input
    keys: [16]bool,

    display: fb.Display,
    screen: [SCREEN_HEIGHT][SCREEN_WIDTH]u8,

    cpu_state: CpuState,

    key_pressed_index: u8,

    ram: *Memory,

    pub fn init() !Cpu {
        const display = try fb.Display.init();

        return Cpu{
            .pc = 0x200,
            .v = std.mem.zeroes([16]u8),
            .ir = 0,
            .sp = 0,
            .stack = std.mem.zeroes([64]u16),
            .display = display,
            .screen = std.mem.zeroes([SCREEN_HEIGHT][SCREEN_WIDTH]u8),
            .delay_timer = 0,
            .sound_timer = 0,
            .keys = [_]bool{false} ** 16,
            .cpu_state = CpuState.Running,
            .rnd = std.rand.DefaultPrng.init(0),
            .key_pressed_index = 0,
            .ram = undefined,
        };
    }

    pub fn run(self: *Cpu, ram: *Memory) !void {
        // var runLen: i32 = 20;
        // const runLen = memory.len

        defer self.display.destroy();
        self.ram = ram;

        var render_tick: usize = 0;
        var timer_tick: usize = SDL.getTicks();

        while (true) {
            if (SDL.getTicks() - timer_tick >= 16) {
                self.handleTimers();
                timer_tick = SDL.getTicks();
            }

            const ev = self.display.getEvent();
            switch (ev.kind) {
                .None => {},
                .Quit => return,
                .KeyUp => {
                    try self.updateKey(ev.data, false);
                },
                .KeyDown => {
                    try self.updateKey(ev.data, true);
                },
            }

            if (self.cpu_state == CpuState.Running) {
                _ = self.execute() catch return;
            }

            SDL.delay(1);

            if (SDL.getTicks() - render_tick >= 16) {
                self.display.redraw(&self.screen) catch return;
                render_tick = SDL.getTicks();
            }
        }

        // var next_time: u64 = 1600; // 1600 microseconds
        //
        // while (true) {
        //     if (self.cpu_state == CpuState.Running) {
        //         std.log.debug("running", .{});
        //
        //         next_time = self.execute() catch 160;
        //     }
        //
        //     std.time.sleep(next_time * TIME_MULT); // into nanoseconds
        //     self.display.redraw(&self.screen) catch break;
        //
        //     std.log.debug("cpu state {any}", .{self.cpu_state});
        //
        //     _ = self.nextTick();
        //
        //     while (true) {
        //         const ev = self.display.getEvent();
        //         switch (ev.kind) {
        //             .None => break,
        //             .Quit => return,
        //             .KeyUp => {
        //                 try self.updateKey(ev.data, false);
        //             },
        //             .KeyDown => {
        //                 try self.updateKey(ev.data, true);
        //             },
        //         }
        //     }
        // }

        std.log.debug("register state {any}", .{self.v});
        return;
    }

    fn getMappedKey(key: SDL.Scancode) ?u16 {
        var chip8Key: ?u16 = undefined;

        switch (key) {
            .@"1" => chip8Key = 0x1,
            .@"2" => chip8Key = 0x2,
            .@"3" => chip8Key = 0x3,
            .@"4" => chip8Key = 0xc,
            .q => chip8Key = 0x4,
            .w => chip8Key = 0x5,
            .e => chip8Key = 0x6,
            .r => chip8Key = 0xd,
            .a => chip8Key = 0x7,
            .s => chip8Key = 0x8,
            .d => chip8Key = 0x9,
            .f => chip8Key = 0xe,
            .z => chip8Key = 0xa,
            .x => chip8Key = 0x0,
            .c => chip8Key = 0xb,
            .v => chip8Key = 0xf,
            else => return undefined,
        }

        return chip8Key;
    }

    fn updateKey(self: *Cpu, key: SDL.Scancode, pressed: bool) !void {
        const mappedKey = getMappedKey(key);

        if (mappedKey) |value| {
            if (value > 0xf) {
                return; //ExecutionError.UnregisteredKey;
            }
            if (self.cpu_state == CpuState.IOWaiting and !pressed) { // and self.keys[value] != pressed
                self.cpu_state = CpuState.Running;
                self.v[self.key_pressed_index] = @intCast(value);
            }

            std.log.debug("key pressed {any} {any} {any} {any}", .{ key, pressed, value, self.keys[value] });
            self.keys[value] = pressed;
        }
    }

    fn handleTimers(self: *Cpu) void {
        if (self.delay_timer > 0) {
            self.delay_timer -= 1;
        }

        if (self.sound_timer > 0) {
            self.sound_timer -= 1;
        }
    }

    pub fn doEf(self: *Cpu, x: u8, nn: u8) !u32 {
        const memory = &self.ram.memory;
        // validate x in range of self.v

        try switch (nn) {
            0x07 => { //FX07
                self.v[x] = self.delay_timer;

                return times.GET_DELAY_TIMER;
            },
            0x0a => { //FX0A
                // we store the register x,
                // on key_pressed_index,
                // we set the value of V(x)
                self.key_pressed_index = x;
                self.cpu_state = CpuState.IOWaiting;

                return times.GET_KEY;
            },
            0x15 => { // FX15
                self.delay_timer = self.v[x];
                return times.GET_DELAY_TIMER;
            },
            0x18 => { //FX18
                self.sound_timer = self.v[x];
                return times.SET_SOUND_TIMER;
            },
            0x1e => { //FX1E
                const result = @addWithOverflow(self.v[x], self.ir);

                self.ir = result[0];
                return times.ADD_TO_INDEX;
            },
            0x29 => { //FX29
                // for rendeirng value (self.v[x]=) 3
                // since each value is 5 byte
                // for n its n * 5
                self.ir = (self.v[x] & 0xf) * 5;

                return times.SET_FONT;
            },
            0x33 => { //FX33
                const number = self.v[x];

                memory[self.ir] = number / 100;
                memory[self.ir + 1] = (number % 100) / 10;
                memory[self.ir + 2] = number % 10;

                return times.BCD;
            },
            0x55 => { //FX55
                var i: u4 = 0;
                while (i <= x) : (i += 1) {
                    memory[self.ir + i] = self.v[i];
                }

                return times.STORE_MEM;
            },
            0x65 => { //FX65
                var i: u4 = 0;
                while (i <= x) : (i += 1) {
                    self.v[i] = memory[self.ir + i];
                }

                return times.LOAD_MEM;
            },
            else => return ExecutionError.InvalidInstruction,
        };

        return 0;
    }

    fn checkBitAndShift(self: *Cpu, xreg: u8, msb: bool) void {
        //8XYE
        var bit: u8 = undefined;
        if (msb) {
            bit = 0x80;
        } else {
            bit = 0x1;
        }

        if (self.v[xreg] & bit == bit) {
            self.v[0xf] = 1;
        } else {
            self.v[0xf] = 0;
        }

        if (msb) {
            self.v[xreg] = self.v[xreg] << 1;
        } else {
            self.v[xreg] = self.v[xreg] >> 1;
        }
    }

    pub fn doMath(self: *Cpu, op: u8, x: u8, y: u8) !void {
        try switch (op) {
            //8XY1 to 8XY3
            0 => self.v[x] = self.v[y],
            1 => self.v[x] |= self.v[y],
            2 => self.v[x] &= self.v[y],
            3 => self.v[x] ^= self.v[y],
            4 => { //8XY4
                const res = @addWithOverflow(self.v[x], self.v[y]);
                self.v[x] = res[0];

                self.v[0xf] = if (res[1] > 0) 1 else 0;
            },
            5 => { //8XY5
                const res = @subWithOverflow(self.v[x], self.v[y]);
                self.v[x] = res[0];

                self.v[0xf] = if (self.v[x] >= self.v[y]) 1 else 0;
            },
            6 => { //8XY6
                // get least significant bit
                self.checkBitAndShift(x, false);
            },
            7 => { //8XY7
                const res = @subWithOverflow(self.v[y], self.v[x]);
                self.v[x] = res[0];

                self.v[0xf] = if (self.v[y] >= self.v[x]) 1 else 0;
            },
            0xe => { //8XYE
                // most sb
                self.checkBitAndShift(x, true);
            },
            else => ExecutionError.UnknownInstruction,
        };
    }

    // Works on a fetch decode execute cycle
    // In case of Chip8 we only need decode and execute
    // Fetch also can be inside this, since its quite simple
    pub fn execute(self: *Cpu) !u32 {
        const memory = &self.ram.memory;

        var next_time: u32 = 0;

        if (self.pc + 1 > 0x1000) {
            return ExecutionError.OutOfMemory;
        }

        const lo: u8 = memory[self.pc];
        const hi: u8 = memory[self.pc + 1];
        const prev_pc = self.pc;

        self.pc += 2;

        var instruction: u16 = 0;
        instruction = ((instruction | lo) << 8) | hi;

        const address: u16 = instruction & 0x0FFF;
        const nn: u8 = @intCast(instruction & 0x00FF);
        const n: u8 = @intCast(instruction & 0x000F);

        // std.log.debug("address 0x{x}", .{address});
        // last 4 bits of starting byte
        const x: u8 = @intCast((instruction & 0x0F00) >> 8);

        // first 4 bits of the ending byte
        const y: u8 = @intCast((instruction & 0x00F0) >> 4);

        // std.log.debug("memory {any}", .{memory});
        // std.log.debug("value at address 0x{x:0>4} 0x{x:0>4}", .{ address, memory[address] });
        const debug_log =
            \\log: instruction: 0x{x:0>4}
            \\prev_pc: 0x{x:0>4}
            \\pc: 0x{x:0>4}
            \\ir: 0x{x:0>4}
            \\sp: 0x{x:0>4}
            \\nnn: 0x{x:0>4} nn: 0x{x:0>4} n: 0x{x:0>4} 
            \\x: 0x{x:0>2} y: 0x{x:0>2}
            \\registers: {any}
            \\vy: 0x{x:0>4} vx: 0x{x:0>4}
        ;

        std.log.debug(debug_log, .{
            instruction,
            prev_pc,
            self.pc,
            self.ir,
            self.sp,
            address,
            nn,
            n,
            x,
            y,
            self.v,
            self.v[y],
            self.v[x],
        });

        try switch ((instruction & 0xF000) >> 12) {
            0x0 => {
                switch (address) {
                    0x00e0 => {
                        self.display.clearScreen(&self.screen);
                        next_time = times.CLEAR_SCREEN;
                    },
                    0x00ee => {
                        self.sp -= 1;
                        self.pc = self.stack[self.sp];
                        next_time = times.RETURN;
                    },
                    else => return ExecutionError.InvalidInstruction,
                }
            },
            0x1 => { //2NNN
                // if (address > 0x1000) {
                //     return ExecutionError.OutOfMemory;
                // }
                self.pc = address;
                next_time = times.JUMP;
            },
            0x2 => {
                // std.log.debug("call subroutine", .{});
                self.stack[self.sp] = self.pc;
                self.sp += 1;
                self.pc = address;

                next_time = times.CALL;
            },
            0x3 => {
                // std.log.debug("0x3XNN cond equal", .{});
                if (self.v[x] == nn) {
                    self.pc += 2;
                }

                next_time = times.SKIP_3X;
            },
            0x4 => {
                // std.log.debug("0x4XNN cond not equal", .{});
                if (self.v[x] != nn) {
                    self.pc += 2;
                }

                next_time = times.SKIP_4X;
            },
            0x5 => {
                // std.log.debug("0x5XY0 increment pc if v[x] == v[y]", .{});
                if (n == 0 and self.v[x] == self.v[y]) {
                    self.pc += 2;
                }

                next_time = times.SKIP_5X;
            },
            0x6 => {
                // std.log.debug("0x6XNN assign nn to x", .{});
                self.v[x] = nn;

                next_time = times.SET_REGISTER;
            },
            0x7 => {
                // std.log.debug("add without carry 0x7XNN", .{});

                const res = @addWithOverflow(self.v[x], nn);
                self.v[x] = res[0];

                next_time = times.ADD;
            },
            0x8 => {
                // std.log.debug("do math 0x8XYN", .{});
                try self.doMath(n, x, y);

                next_time = times.ARITHMETIC;
            },
            0x9 => {
                // std.log.debug("cond 0x9 skip to NN", .{});

                if (n == 0 and self.v[x] != self.v[y]) {
                    self.pc += 2;
                }

                next_time = times.SKIP_9X;
            },
            0xA => {
                // std.log.debug("0xA set instruction pointer", .{});
                self.ir = address;

                next_time = times.SET_INDEX;
            },
            0xB => {
                // std.log.debug("0xBNNN jump to NNN", .{});
                const v0: u16 = self.v[0];
                self.pc = address + v0;

                next_time = times.JUMP_WITH_OFFSET;
            },
            0xC => {
                // std.log.debug("0xCXNN set vx to rand() & nn", .{});
                const randnum: u8 = self.rnd.random().int(u8);
                self.v[x] = randnum & nn;

                next_time = times.GET_RANDOM;
            },
            0xD => {
                // std.log.debug("0xDXYN display N height at XY", .{});
                const vx = self.v[x] & 63; // clamp the value to screen width
                const vy = self.v[y] & 31; // clamp the value to screen height

                try self.draw(vx, vy, n);

                next_time = times.DRAW;
            },
            0xE => {
                // std.log.debug("0xE handle keyboard event. 0x{x:0>4}", .{instruction});
                const key = self.v[x] & 0xf;

                switch (nn) {
                    0x9E => {
                        if (self.keys[key]) {
                            self.pc += 2;
                        }
                    },
                    0xA1 => {
                        if (!self.keys[key]) {
                            self.pc += 2;
                        }
                    },
                    else => return ExecutionError.InvalidInstruction,
                }
                next_time = times.CHECK_KEY;
            },
            0xF => {
                // std.log.debug("0xF handle timer and other stuff 0x{x:0>4}", .{instruction});
                next_time = try self.doEf(x, nn);
            },
            else => ExecutionError.InvalidInstruction,
        };

        if (lo == 0 and hi == 0) {
            return ExecutionError.OutOfMemory;
        }

        return next_time;
    }

    fn draw(self: *Cpu, vx: u8, vy: u8, height: u8) !void {
        const mem = &self.ram.memory;

        self.v[0xf] = 0;

        var n: u4 = 0;
        var y: u8 = vy;

        // and self.ir + n < 0x1000
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

        try self.cpu.run(&self.ram);
        return;
    }
};

pub fn readFile(filename: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer file.close();

    const fileSize = (try file.stat()).size;
    std.log.debug("fileSize {}\n", .{fileSize});

    const buffer = try file.readToEndAlloc(allocator, fileSize);
    return buffer;
}

const CliArgs = struct {
    filename: [:0]const u8,
};

pub fn handle_cli() !CliArgs {
    var buffer: [10000]u8 = undefined;

    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    var arg_iter = try std.process.argsWithAllocator(allocator);
    defer arg_iter.deinit();

    _ = arg_iter.skip();

    const filename = arg_iter.next() orelse "./c8games/INVADERS";

    return CliArgs{ .filename = filename };
}

pub fn main() !void {
    const cliargs = try handle_cli();

    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const gameData = try readFile(cliargs.filename, allocator);
    defer allocator.free(gameData);

    var chip8 = try Chip8.init();
    try chip8.load_game(gameData);
}
