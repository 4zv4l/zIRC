const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const crossline = b.addStaticLibrary(.{
        .name = "crossline",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    crossline.addCSourceFile(.{ .file = .{
        .src_path = .{ .owner = b, .sub_path = "lib/Crossline/crossline.c" },
    }, .flags = &.{"-O3"} });
    crossline.addIncludePath(b.path("lib/Crossline/"));

    const known_folders = b.dependency("known-folders", .{ .optimize = optimize, .target = target });

    const exe = b.addExecutable(.{
        .name = "simple_irc",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("known-folders", known_folders.module("known-folders"));
    exe.addIncludePath(b.path("lib/Crossline/"));
    exe.linkLibrary(crossline);
    b.installArtifact(exe);
}
