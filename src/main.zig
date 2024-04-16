const std = @import("std");

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

const Chip8 = struct {
    ram: Memory,

    pub fn init() Chip8 {
        const ram = Memory{
            .memory = [_]u8{0} ** 0x1000,
            .v = undefined,
            .ir = 0,
            .pc = 0x200,
            .stack = undefined,
            .sp = 0,
            .delay_timer = 0,
            .sound_timer = 0,
            .keys = undefined,
        };
        return Chip8{ .ram = ram };
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

        std.log.info("memory {any}", .{self.ram.memory});
        std.log.info("gameData {any}", .{gameData});
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
    const filename = "./c8games/TICTAC";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const gameData = try readFile(filename, allocator);
    defer allocator.free(gameData);

    // std.log.info("File contents: {any}\n", .{fileContents});

    var chip8 = Chip8.init();
    try chip8.load_game(gameData);
}
