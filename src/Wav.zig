const Wav = @This();

const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

const log = std.log.scoped(.wav);

const FormatCode = enum(u16) {
    pcm = 1,
};

const FormatChunk = packed struct {
    code: FormatCode,
    channels: u16,
    sample_rate: u32,
    byte_rate: u32,
    block_align: u16,
    bits: u16,

    fn parse(reader: anytype, chunk_size: usize) !FormatChunk {
        if (chunk_size < @sizeOf(FormatChunk)) {
            return error.InvalidSize;
        }
        const fmt = try reader.readStruct(FormatChunk);
        if (chunk_size > @sizeOf(FormatChunk)) {
            try reader.skipBytes(chunk_size - @sizeOf(FormatChunk), .{});
        }
        return fmt;
    }
};

pub fn Decoder(comptime InnerReaderType: type) type {
    return struct {
        const Self = @This();

        const ReaderType = std.io.CountingReader(InnerReaderType);
        const Error = ReaderType.Error || error{ EndOfStream, InvalidFileType, InvalidArgument, InvalidSize, InvalidValue, Overflow, Unsupported };

        counting_reader: ReaderType,
        fmt: FormatChunk,
        data_start: usize,
        data_size: usize,

        pub fn sampleRate(self: *const Self) usize {
            return self.fmt.sample_rate;
        }

        pub fn channels(self: *const Self) usize {
            return self.fmt.channels;
        }

        pub fn bits(self: *const Self) usize {
            return self.fmt.bits;
        }

        /// Number of samples remaining.
        pub fn remaining(self: *const Self) usize {
            const sample_size = self.bits() / 8;
            const bytes_remaining = self.data_size + self.data_start - self.counting_reader.bytes_read;

            std.debug.assert(bytes_remaining % sample_size == 0);
            return bytes_remaining / sample_size;
        }

        fn init(inner_reader: InnerReaderType) Error!Self {
            comptime std.debug.assert(builtin.target.cpu.arch.endian() == .little);

            var counting_reader = ReaderType{ .child_reader = inner_reader };
            var reader = counting_reader.reader();

            var chunk_id = try reader.readBytesNoEof(4);
            if (!std.mem.eql(u8, "RIFF", &chunk_id)) {
                std.log.debug("not a RIFF file", .{});
                return error.InvalidFileType;
            }
            const total_size = try std.math.add(u32, try reader.readInt(u32, .little), 8);

            const format = try reader.readBytesNoEof(4);
            if (!std.mem.eql(u8, "WAVE", &format)) {
                std.log.debug("not a WAVE file", .{});
                return error.InvalidFileType;
            }

            // Iterate through chunks. Require fmt and data.
            var fmt: ?FormatChunk = null;
            var data_size: usize = 0;
            var chunk_size: usize = 0;
            while (true) {
                chunk_id = try reader.readBytesNoEof(4);
                chunk_size = try reader.readInt(u32, .little);

                if (std.mem.eql(u8, "fmt", &chunk_id)) {
                    fmt = try FormatChunk.parse(reader, chunk_size);
                } else if (std.mem.eql(u8, "data", &chunk_id)) {
                    data_size = chunk_size;
                    break;
                } else {
                    std.log.info("skipping unrecognized subchunk {s}", .{chunk_id});
                    try reader.skipBytes(chunk_size, .{});
                }
            }

            if (fmt == null) {
                std.log.debug("no fmt chunk present", .{});
                return error.InvalidFileType;
            }

            std.log.info(
                "{}(bits={}) sample_rate={} channels={} size=0x{x}",
                .{ fmt.?.code, fmt.?.bits, fmt.?.sample_rate, fmt.?.channels, total_size },
            );

            const data_start = counting_reader.bytes_read;
            if (data_start + data_size > total_size) {
                return error.InvalidSize;
            }
            if (data_size % (fmt.?.channels * fmt.?.bits / 8) != 0) {
                return error.InvalidSize;
            }

            return .{
                .counting_reader = counting_reader,
                .fmt = fmt.?,
                .data_start = data_start,
                .data_size = data_size,
            };
        }

        // pub fn read(self: *Self, comptime T: type, buf: []T) Error!usize {
        //     return switch (self.fmt.code) {
        //         .pcm => switch (self.fmt.bits) {
        //             8 => self.readInternal(u8, T, buf),
        //             16 => self.readInternal(i16, T, buf),
        //             24 => self.readInternal(i24, T, buf),
        //             32 => self.readInternal(i32, T, buf),
        //             else => std.debug.panic("invalid decoder state, unexpected fmt bits {}", .{self.fmt.bits}),
        //         },
        //         else => std.debug.panic("invalid decoder state, unexpected fmt code {}", .{@intFromEnum(self.fmt.code)}),
        //     };
        // }
        //
        // fn readInternal(self: *Self, comptime S: type, comptime T: type, buf: []T) Error!usize {
        //     var reader = self.counting_reader.reader();
        //
        //     const limit = std.math.min(buf.len, self.remaining());
        //     var i: usize = 0;
        //     while (i < limit) : (i += 1) {
        //         buf[i] = sample.convert(
        //             T,
        //             // Propagate EndOfStream error on truncation.
        //             switch (@typeInfo(S)) {
        //                 .Float => try readFloat(S, reader),
        //                 .Int => try reader.readIntLittle(S),
        //                 else => @compileError(bad_type),
        //             },
        //         );
        //     }
        //     return i;
        // }()
    };
}

pub fn decoder(reader: anytype) !Decoder(@TypeOf(reader)) {
    return Decoder(@TypeOf(reader)).init(reader);
}

test {
    var file = try std.fs.cwd().openFile("src/jfk.wav", .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    _ = try decoder(buf_reader.reader());
}
