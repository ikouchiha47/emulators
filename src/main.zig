const std = @import("std");

// https://en.wikipedia.org/wiki/CHIP-8
// https://github.com/mattmikolay/chip-8/wiki/Mastering-CHIP‐8
// https://austinmorlan.com/posts/chip8_emulator/
// Chip-8 was capable of accessing 4KB of RAM (4096 Bytes)
// Location (0x000) to (0xFFF) (0 to 4095)
const Chip8 = struct {
    // 4KB Memory
    memory: [0x1000]u8,

    //Registers in CPU
    V: [16]u8,

    // CHIP-8 allows memory addressing 2^12,
    // so, 16 bits to cover all the address ranges
    IR: u16,
    PC: u16,

    stack: [16]u16,
    sp: u8,

    // Times
    delay_timer: u8,
    sound_timer: u8,

    // Input
    keys: [16]bool,
};

// Step 1: Read a game file

pub fn readFile(filename: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer file.close();

    const fileSize = (try file.stat()).size;
    std.debug.print("fileSize {}\n", .{fileSize});

    const buffer = try file.readToEndAlloc(allocator, fileSize);
    return buffer;
}

pub fn main() !void {
    std.debug.print("Hello, world!\n", .{});
    const filename = "./c8games/TICTAC";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const fileContents = try readFile(filename, allocator);
    defer allocator.free(fileContents);

    std.debug.print("File contents: {any}\n", .{fileContents});
}
