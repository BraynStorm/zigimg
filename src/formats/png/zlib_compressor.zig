const std = @import("std");
const io = std.io;
const deflate = std.compress.flate;

/// Zlib Compressor (Deflate) with a writer interface
pub fn ZlibCompressor() type {
    return struct {
        raw_writer: *std.Io.Writer,
        compressor: deflate.Compress,
        adler: std.hash.Adler32,

        const Self = @This();

        // TODO: find why doing it an other way segfaults
        /// Inits a zlibcompressor
        /// This is made this way because not doing it in place segfaults for a reason
        pub fn init(self: *Self, writer: *std.Io.Writer) !void {
            _ = writer; // autofix
            self.compressor = try deflate.Compress(self.raw_writer, .{});
            self.adler = std.hash.Adler32.init();
        }

        /// Begins a zlib block with the header
        pub fn begin(self: *Self) !void {
            // TODO: customize
            const compression_method = 0x78; // 8 = deflate, 7 = log(window size (see std.compress.deflate)) - 8
            const compression_flags = blk: {
                var ret: u8 = 0b10000000; // 11 = max compression
                const rem: u8 = @truncate(((@as(usize, @intCast(compression_method)) << 8) + ret) % 31);
                ret += 31 - @as(u8, @truncate(rem));
                break :blk ret;
            };

            //std.debug.assert(((@intCast(usize, cmf) << 8) + flg) % 31 == 0);
            // write the header
            var wr = self.raw_writer;
            try wr.writeByte(compression_method);
            try wr.writeByte(compression_flags);
        }

        pub fn write(self: *Self, bytes: []const u8) Error!usize {
            const amount = try self.compressor.writer().write(bytes);
            self.adler.update(bytes[0..amount]);
            return amount;
        }

        /// Ends a zlib block with the checksum
        pub fn end(self: *Self) !void {
            // Write the checksum
            try self.compressor.end();
            try self.raw_writer.writeInt(u32, self.adler.final(), .big);
        }
    };
}
