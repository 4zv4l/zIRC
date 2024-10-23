const std = @import("std");
const io = std.io;
const net = std.net;
const log = std.log;
const Thread = std.Thread;
const Colors = @import("colors.zig").colors;
const IRC = @import("irc.zig");
const cr = @cImport(@cInclude("crossline.h"));
const known_folder = @import("known-folders");

pub const std_options = std.Options{ .log_level = .debug };
const prompt = ">>> ";

pub fn sendMessageLoop(irc: *IRC) void {
    var quit = false;
    var buff: [2048]u8 = undefined;
    while (!quit) {
        const line: []u8 = std.mem.span(cr.crossline_readline(prompt, &buff, buff.len) orelse return);
        if (line.len == 0) continue;

        if (std.mem.eql(u8, "quit", line) or std.mem.eql(u8, "QUIT", line)) quit = true;
        irc.bwriter.writer().print("{s}\n", .{line}) catch return;
        irc.bwriter.flush() catch return;
    }
}

pub fn recvMessageLoop(irc: *IRC) void {
    var buffer: [1024]u8 = undefined;
    while (true) {
        const m = irc.eventLoop(&buffer) catch |e| switch (e) {
            error.EndOfStream => return std.debug.print("\r", .{}),
            else => @panic(@errorName(e)),
        };

        // TODO: improve this
        if (m.cmd) |msg| {
            std.debug.print("\r{}\n{s}", .{ msg, prompt });
        } else {
            std.debug.print("\r{s}{s}{s}\n{s}", .{ Colors.light_red, buffer[0..m.len], Colors.reset, prompt });
        }
    }
}

pub fn getSaveHistoryPath(allocator: std.mem.Allocator) ![:0]u8 {
    if (try known_folder.getPath(allocator, .home)) |dir_path| {
        defer allocator.free(dir_path);
        return try std.fs.path.joinZ(allocator, &.{ dir_path, ".zIRC_history" });
    } else {
        return try std.fs.path.joinZ(allocator, &.{ ".", ".zIRC_history" });
    }
}

pub fn saveHistory(allocator: std.mem.Allocator) !void {
    const save_history_path = try getSaveHistoryPath(allocator);
    defer allocator.free(save_history_path);
    log.debug("saving to: {s}", .{save_history_path});
    if (cr.crossline_history_save(save_history_path) != 0) return error.SaveHistory;
}

pub fn loadHistory(allocator: std.mem.Allocator) !void {
    const save_history_path = try getSaveHistoryPath(allocator);
    defer allocator.free(save_history_path);
    log.debug("loading from: {s}", .{save_history_path});
    if (cr.crossline_history_load(save_history_path) != 0) return error.LoadHistory;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 4 or args.len > 6) {
        return std.debug.print("usage: {s} [host] [port] <tls> [nick] <user>\n", .{args[0]});
    }

    const config = .{
        .hostname = args[1],
        .port = try std.fmt.parseUnsigned(u16, args[2], 10),
        .tls = std.mem.eql(u8, args[3], "tls"),
        .nick = if (args.len == 4) args[3] else args[4],
        .user = args[args.len - 1],
    };
    log.debug("using tls: {}", .{config.tls});
    var irc = try IRC.init(allocator, config);
    defer irc.deinit();

    loadHistory(allocator) catch log.warn("Couldnt load the input history", .{});

    const recv_th = try Thread.spawn(.{}, recvMessageLoop, .{&irc});
    const send_th = try Thread.spawn(.{}, sendMessageLoop, .{&irc});
    send_th.join();
    recv_th.join();

    saveHistory(allocator) catch log.warn("Couldnt save the input history", .{});
}
