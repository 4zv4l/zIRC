const std = @import("std");
const ally = std.heap.page_allocator;

pub fn doBuild(b: *std.Build, query: std.Target.Query, optimize: std.builtin.OptimizeMode) !void {
    //const target = b.standardTargetOptions(.{});
    const target = b.resolveTargetQuery(query);
    //const optimize = b.standardOptimizeOption(.{});

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

    const binname = try std.fmt.allocPrint(ally, "zIRC-{s}-{s}", .{
        @tagName(query.cpu_arch.?),
        @tagName(query.os_tag.?),
    });
    defer ally.free(binname);

    const exe = b.addExecutable(.{
        .name = binname,
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("known-folders", known_folders.module("known-folders"));
    exe.addIncludePath(b.path("lib/Crossline/"));
    exe.linkLibrary(crossline);
    b.installArtifact(exe);
}

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const queries = &[_]std.Target.Query{
        std.Target.Query{ .os_tag = .windows, .cpu_arch = .x86_64 },
        std.Target.Query{ .os_tag = .linux, .cpu_arch = .x86_64, .abi = .musl },
        std.Target.Query{ .os_tag = .macos, .cpu_arch = .aarch64 },
    };
    for (queries) |query| try doBuild(b, query, optimize);
}
