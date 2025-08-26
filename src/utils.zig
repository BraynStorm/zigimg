const builtin = @import("builtin");
const std = @import("std");

const native_endian = builtin.target.cpu.arch.endian();

pub const StructReadError =
    // std.io.StreamSource.ReadError ||
    error{ EndOfStream, ReadFailed, InvalidData };
pub const StructWriteError =
    // std.io.StreamSource.WriteError ||
    error{WriteFailed};

pub fn FixedStorage(comptime T: type, comptime storage_size: usize) type {
    return struct {
        data: []T = &.{},
        storage: [storage_size]T = undefined,

        const Self = @This();

        pub fn resize(self: *Self, size: usize) void {
            self.data = self.storage[0..size];
        }
    };
}

pub fn toMagicNumberNative(magic: []const u8) u32 {
    var result: u32 = 0;
    for (magic, 0..) |character, index| {
        result |= (@as(u32, character) << @intCast((index * 8)));
    }
    return result;
}

pub fn toMagicNumberForeign(magic: []const u8) u32 {
    var result: u32 = 0;
    for (magic, 0..) |character, index| {
        result |= (@as(u32, character) << @intCast((magic.len - 1 - index) * 8));
    }
    return result;
}

pub inline fn toMagicNumber(magic: []const u8, comptime wanted_endian: std.builtin.Endian) u32 {
    return switch (native_endian) {
        .little => {
            return switch (wanted_endian) {
                .little => toMagicNumberNative(magic),
                .big => toMagicNumberForeign(magic),
            };
        },
        .big => {
            return switch (wanted_endian) {
                .little => toMagicNumberForeign(magic),
                .big => toMagicNumberNative(magic),
            };
        },
    };
}

fn checkEnumFields(data: anytype) StructReadError!void {
    const T = @typeInfo(@TypeOf(data)).pointer.child;
    inline for (std.meta.fields(T)) |entry| {
        switch (@typeInfo(entry.type)) {
            .@"enum" => {
                const value = @intFromEnum(@field(data, entry.name));
                _ = std.meta.intToEnum(entry.type, value) catch return StructReadError.InvalidData;
            },
            .@"struct" => {
                try checkEnumFields(&@field(data, entry.name));
            },
            else => {},
        }
    }
}

pub inline fn readStruct(reader: *std.Io.Reader, comptime T: type, comptime wanted_endian: std.builtin.Endian) StructReadError!T {
    var result: T = try reader.takeStruct(T, wanted_endian);
    try checkEnumFields(&result);
    return result;
}

pub inline fn writeStruct(writer: *std.Io.Writer, value: anytype, comptime wanted_endian: std.builtin.Endian) StructWriteError!void {
    try writer.writeStruct(value, wanted_endian);
}
