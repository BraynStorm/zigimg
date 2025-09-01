const std = @import("std");

const Crc = std.hash.crc.Crc32;
pub const BufferSize = 1 << 14; // 16 kb

/// Writer based on buffered writer that will write whole chunks of data of [buffer size]
pub const ChunkWriter = struct {
    interface: std.Io.Writer,
    section_id: [4]u8,
    underlying_writer: *std.Io.Writer,

    const Self = @This();

    pub fn flush(w: *std.Io.Writer) !void {
        const self: *Self = @fieldParentPtr("interface", w);

        try self.underlying_writer.writeInt(u32, @as(u32, @truncate(w.end)), .big);

        var crc = Crc.init();

        crc.update(&self.section_id);
        try self.underlying_writer.writeAll(&self.section_id);

        crc.update(w.buffer[0..w.end]);
        try self.underlying_writer.writeAll(w.buffer[0..w.end]);

        try self.underlying_writer.writeInt(u32, crc.final(), .big);

        w.end = 0;
    }
};

pub fn chunkWriter(underlying_writer: *std.Io.Writer, buffer: *[BufferSize]u8, comptime id: []const u8) ChunkWriter {
    if (id.len != 4)
        @compileError("PNG chunk id must be 4 characters");

    return .{
        .underlying_writer = underlying_writer,
        .section_id = std.mem.bytesToValue([4]u8, id[0..4]),
        .interface = .{
            .buffer = buffer,
            .end = 0,
            .vtable = &.{
                .drain = std.Io.Writer.fixed(&.{}).vtable.drain,
                .flush = &ChunkWriter.flush,
                .rebase = std.Io.Writer.fixed(&.{}).vtable.rebase,
            },
        },
    };
}

// TODO: test idat writer
