const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("whisper", .{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const whisperCpp = b.dependency("whisper.cpp", .{});
    const lib = b.addStaticLibrary(.{
        .name = "whisper",
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    lib.linkLibCpp();
    if (lib.root_module.resolved_target.?.result.os.tag == .linux) {
        lib.defineCMacro("_GNU_SOURCE", "");
    }

    // const dynamic_link_opts: std.Build.Module.LinkSystemLibraryOptions = .{
    //     .preferred_link_mode = .dynamic,
    //     .search_strategy = .mode_first,
    // };

    lib.addIncludePath(whisperCpp.path(""));
    module.addIncludePath(whisperCpp.path(""));

    lib.addCSourceFile(.{ .file = whisperCpp.path("whisper.cpp") });
    lib.addCSourceFile(.{ .file = whisperCpp.path("ggml.c") });
    lib.addCSourceFile(.{ .file = whisperCpp.path("ggml-alloc.c") });
    lib.addCSourceFile(.{ .file = whisperCpp.path("ggml-backend.c") });
    lib.addCSourceFile(.{ .file = whisperCpp.path("ggml-quants.c") });

    b.installArtifact(lib);
}
