const std = @import("std");
const io = std.io;
const net = std.net;
const log = std.log;
const Thread = std.Thread;
const Colors = @import("colors.zig").colors;
const IRC = @import("irc.zig");

pub const std_options = std.Options{ .log_level = .debug };

pub fn sendMessageLoop(irc: *IRC) void {
    // user input loop
    var input_buffer: [4096]u8 = undefined;
    var stdin = std.io.getStdIn().reader();
    var quit = false;
    while (!quit) {
        std.debug.print("\x1b[92;1m>>>\x1b[0m ", .{});
        const line = stdin.readUntilDelimiter(&input_buffer, '\n') catch continue;
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

        // to make better
        if (m.cmd) |msg| {
            std.debug.print("{}", .{msg});
        } else {
            std.debug.print("\r{s}{s}{s}\n", .{ Colors.light_red, buffer[0..m.len], Colors.reset });
        }
        std.debug.print("\x1b[92;1m>>>\x1b[0m ", .{}); // reprint the prompt
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 4) {
        return std.debug.print("usage: {s} [host] [port] [nick] <user>\n", .{args[0]});
    }

    const config = .{
        .hostname = args[1],
        .port = try std.fmt.parseUnsigned(u16, args[2], 10),
        .nick = args[3],
        .user = if (args.len == 5) args[4] else args[3],
    };
    var irc = try IRC.init(allocator, config);
    defer irc.deinit();

    const recv_th = try Thread.spawn(.{}, recvMessageLoop, .{&irc});
    const send_th = try Thread.spawn(.{}, sendMessageLoop, .{&irc});
    send_th.join();
    recv_th.join();
}
