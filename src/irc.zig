const std = @import("std");
const io = std.io;
const net = std.net;
const log = std.log;
const Cmd = @import("commands.zig").Cmd;

const IRC = @This();

const colors = .{
    .light_grey = "\x1b[38;5;8m",
    .light_red = "\x1b[38;5;1m",
    .reset = "\x1b[0m",
};

stream: net.Stream,
ally: std.mem.Allocator,
breader: io.BufferedReader(4096, net.Stream.Reader) = undefined,
bwriter: io.BufferedWriter(4096, net.Stream.Writer) = undefined,

// connect to the IRC server and register to it
pub fn init(ally: std.mem.Allocator, config: anytype) !IRC {
    const stream = try net.tcpConnectToHost(ally, config.hostname, config.port);
    var irc = IRC{
        .stream = stream,
        .ally = ally,
        .breader = io.bufferedReader(stream.reader()),
        .bwriter = io.bufferedWriter(stream.writer()),
    };
    try irc.handshake(config.nick, config.user);
    return irc;
}

// close the connection to the IRC server
pub fn deinit(self: *IRC) void {
    self.stream.close();
}

// register to the server
pub fn handshake(self: *IRC, nickname: []const u8, username: []const u8) !void {
    std.debug.print("{s}NICK {s}{s}\n", .{ colors.light_grey, nickname, colors.reset });
    try self.bwriter.writer().print("NICK {s}\n", .{nickname});
    std.debug.print("{s}USER {s} 0 * :Zig IRC Client{s}\n", .{ colors.light_grey, username, colors.reset });
    try self.bwriter.writer().print("USER {s} 0 * :Zig IRC Client\n", .{username});
    try self.bwriter.flush();
}

// get message from server and return them as Msg struct
pub fn eventLoop(self: *IRC) !Cmd {
    while (true) {
        // will be freed by the root.recvMessageLoop
        const line = try self.breader.reader().readUntilDelimiterAlloc(self.ally, '\n', 1 * 1024 * 1024); // 1mb
        errdefer self.ally.free(line);
        // parse or show row
        const cmd = Cmd.parse(line);
        // handling PING
        if (cmd.cmd == .ping) {
            try self.bwriter.writer().print("PONG {s}\n", .{cmd.cmd.ping.ping});
            try self.bwriter.flush();
        }
        return cmd;
    }
}
