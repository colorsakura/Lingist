const Whisper = @This();

const std = @import("std");
const c = @import("whisper").c;

const log = std.log.scoped(.whisper);

ws_ctx: *c.whisper_context,

pub fn init(self: *Whisper) !void {
    const whisper_params = c.whisper_context_default_params();
    const model: []const u8 = @embedFile("../models/ggml-base.bin");
    const ws_ctx = c.whisper_init_from_buffer_with_params(@ptrCast(model.ptr), model.len, whisper_params);
    errdefer c.whisper_free(ws_ctx);

    self.* = .{
        .ws_ctx = ws_ctx,
    };
}
