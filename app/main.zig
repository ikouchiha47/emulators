const std = @import("std");
const times = @import("times.zig");
const SDL = @import("sdl2");

const SCREEN_WIDTH = 64;
const SCREEN_HEIGHT = 32;
const TIME_MULT = 1000;

pub const std_options = .{ .log_level = .info };

// Chip-8 was capable of accessing 4KB of RAM (4096 Bytes)
// Location (0x000) to (0xFFF) (0 to 4095)
const Memory = struct {
    // 4KB Memory
    memory: [0x10000]u8,

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

const ExecutionError = error{
    OutOfMemory,
    InvalidInstruction,
    UnknownInstruction,
    UnregisteredKey,
};

const CpuState = enum {
    Running,
    IOWaiting,
};

const Cpu = struct {
    rnd: std.rand.Xoshiro256,
};

const Chip8 = struct {
    ram: Memory,
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
}
