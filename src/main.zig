const std = @import("std");
const whisper = @import("whisper");

pub fn main() !void {
    const whisper_params = whisper.c.whisper_context_default_params();
    const model: []const u8 = @embedFile("models/ggml-base.bin");
    const ws_ctx: *whisper.c.whisper_context =
        whisper.c.whisper_init_from_buffer_with_params(@constCast(model.ptr), model.len, whisper_params) orelse {
        std.log.err("Failed to create whisper context", .{});
        return error.Whisper;
    };
    errdefer whisper.c.whisper_free(ws_ctx);

    var params = whisper.c.whisper_full_default_params(whisper.c.WHISPER_SAMPLING_BEAM_SEARCH);
    params.max_len = 1;
    params.token_timestamps = true;
    params.abort_callback = abortCallback;

    // _ = try whisper.c.whisper_full();
}

fn abortCallback(userdata: ?*anyopaque) callconv(.C) bool {
    const val: *std.atomic.Value(bool) = @ptrCast(@alignCast(userdata));
    return val.load(std.builtin.AtomicOrder.unordered);
}
