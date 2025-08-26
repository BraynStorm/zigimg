const std = @import("std");
const ImageUnmanaged = @import("ImageUnmanaged.zig");
const color = @import("color.zig");

// mlarouche: Because this is a interface, I use Zig function naming convention instead of the variable naming convention
formatDetect: *const FormatDetectFn,
readImage: *const ReadImageFn,
writeImage: *const WriteImageFn,

pub const FormatDetectFn = fn (stream: *std.Io.Reader) ImageUnmanaged.ReadError!bool;
pub const ReadImageFn = fn (allocator: std.mem.Allocator, stream: *std.Io.Reader) ImageUnmanaged.ReadError!ImageUnmanaged;
pub const WriteImageFn = fn (allocator: std.mem.Allocator, write_stream: *std.Io.Writer, image: ImageUnmanaged, encoder_options: ImageUnmanaged.EncoderOptions) ImageUnmanaged.WriteError!void;
