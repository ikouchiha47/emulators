const Registers = struct {
    a: u8, // accumulator
    f: u8, // flag
    b: u8,
    c: u8,
    d: u8,
    e: u8,
    h: u8,
    l: u8,

    sp: u16,
    pc: u16,

    pub fn get_af(self: *Registers) u16 {
        const instruction: u16 = 0;
        return ((instruction | self.a) << 8) | self.f;
    }

    pub fn get_bc(self: *Registers) u16 {
        const instruction: u16 = 0;
        return ((instruction | self.b) << 8) | self.c;
    }

    pub fn get_hl(self: *Registers) u16 {
        const instruction: u16 = 0;
        return ((instruction | self.h) << 8) | self.l;
    }

    pub fn init() Registers {
        return {
            return Registers{
                .a = 0,
                .f = 0,
                .b = 0,
                .c = 0,
                .d = 0,
                .e = 0,
                .h = 0,
                .l = 0,
                .sp = 0,
                .pc = 0,
            };
        };
    }
};

const Memory = struct {
    memory: [0xffff]u8,

    cpu: *Registers,

    pub fn init(regs: *Registers) Memory {
        const memory = [_]u8{0} ** 0xfff;

        return Memory{
            .memory = memory,
            .cpu = regs,
        };
    }
};
