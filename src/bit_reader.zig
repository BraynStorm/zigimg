const std = @import("std");

fn Bits(comptime T: type) type {
    return struct { T, u16 };
}

const low_bit_mask = [9]u8{
    0b00000000,
    0b00000001,
    0b00000011,
    0b00000111,
    0b00001111,
    0b00011111,
    0b00111111,
    0b01111111,
    0b11111111,
};

pub const BitReader = struct {
    bytes: []const u8,
    index: usize = 0,
    bits: u8 = 0,
    count: u4 = 0,

    fn initBits(comptime T: type, out: anytype, num: u16) Bits(T) {
        const UT = std.meta.Int(.unsigned, @bitSizeOf(T));
        return .{
            @bitCast(@as(UT, @intCast(out))),
            num,
        };
    }

    pub fn readBitsNoEof(self: *@This(), comptime T: type, num: u16) !T {
        const b, const c = try self.readBitsTuple(T, num);
        if (c < num) return error.EndOfStream;
        return b;
    }

    pub fn readBits(self: *@This(), comptime T: type, num: u16, out_bits: *u16) !T {
        const b, const c = try self.readBitsTuple(T, num);
        out_bits.* = c;
        return b;
    }

    fn readBitsTuple(self: *@This(), comptime T: type, num: u16) !Bits(T) {
        const UT = std.meta.Int(.unsigned, @bitSizeOf(T));
        const U = if (@bitSizeOf(T) < 8) u8 else UT;

        if (num <= self.count) return initBits(T, self.removeBits(@intCast(num)), num);

        var out_count: u16 = self.count;
        var out: U = self.removeBits(self.count);

        const full_bytes_left = (num - out_count) / 8;

        for (0..full_bytes_left) |_| {
            const byte = takeByte(self) catch |err| switch (err) {
                error.EndOfStream => return initBits(T, out, out_count),
            };

            const pos = @as(U, byte) << @intCast(out_count);
            out |= pos;
            out_count += 8;
        }

        const bits_left = num - out_count;
        const keep = 8 - bits_left;

        if (bits_left == 0) return initBits(T, out, out_count);

        const final_byte = takeByte(self) catch |err| switch (err) {
            error.EndOfStream => return initBits(T, out, out_count),
        };

        const pos = @as(U, final_byte & low_bit_mask[bits_left]) << @intCast(out_count);
        out |= pos;
        self.bits = final_byte >> @intCast(bits_left);

        self.count = @intCast(keep);
        return initBits(T, out, num);
    }

    fn takeByte(br: *BitReader) error{EndOfStream}!u8 {
        if (br.bytes.len - br.index == 0) return error.EndOfStream;
        const result = br.bytes[br.index];
        br.index += 1;
        return result;
    }

    fn removeBits(self: *@This(), num: u4) u8 {
        if (num == 8) {
            self.count = 0;
            return self.bits;
        }

        const keep = self.count - num;
        const bits = self.bits & low_bit_mask[num];
        self.bits >>= @intCast(num);
        self.count = keep;
        return bits;
    }

    fn alignToByte(self: *@This()) void {
        self.bits = 0;
        self.count = 0;
    }
};

const builtin = @import("builtin");

pub const RealBitReader = struct {
    source: *std.Io.Reader,
    seek_bits: u4 = 0,
    last_byte: u8 = 0,

    comptime {
        std.debug.assert(@sizeOf(usize) >= @sizeOf(u16));
    }

    pub fn readBits(self: *@This(), comptime T: type, n_bits: u16, out_bits: *u16) !T {
        std.debug.assert(n_bits > 0);

        const total_bits = n_bits + self.seek_bits;
        std.debug.assert(total_bits <= 64);

        const n_bytes = @divFloor(total_bits, 8) + 1;
        std.debug.assert(n_bytes <= @sizeOf(usize));

        const buffered_len = self.source.bufferedLen();
        const to_be_read = @min(buffered_len, n_bytes);
        out_bits.* = @min(to_be_read * 8 - self.seek_bits, n_bits);

        //- bs: read bits rounded up to the next multiple of 8
        var result: usize = 0;
        for (self.source.peek(to_be_read) catch |e| switch (e) {
            error.EndOfStream => unreachable,
            else => return e,
        }, 0..) |b, i| {
            const byte: usize = b;
            switch (comptime builtin.cpu.arch.endian()) {
                .little => {
                    result |= byte << @as(u6, @intCast(i * 8));
                },
                .big => {
                    result = (result << 8) | byte;
                },
            }
        }
        //- bs: skip the bits that were leftover from the last read operation.
        result >>= self.seek_bits;

        //- bs: remove extra upper bits we've read
        result &= ~((~@as(usize, 0)) << @intCast(n_bits));

        //- bs: toss everything we've fully read.
        self.source.toss(n_bytes - 1);

        //- bs: remember what we need to skip from the next read.
        self.seek_bits = @intCast(total_bits % 8);

        // std.debug.print("reading {d} bits. Out={d}, R={b}\n", .{ n_bits, out_bits.*, result });

        return @intCast(result);
    }
};
