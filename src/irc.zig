const std = @import("std");
const io = std.io;
const net = std.net;
const log = std.log;
const tls = std.crypto.tls;
const Cmd = @import("commands.zig").Cmd;

const IRC = @This();

const colors = .{
    .light_grey = "\x1b[38;5;8m",
    .light_red = "\x1b[38;5;1m",
    .reset = "\x1b[0m",
};

stream: net.Stream,
bundle: ?*std.crypto.Certificate.Bundle = null,
ally: std.mem.Allocator,
breader: io.BufferedReader(4096, WrapStream) = undefined,
bwriter: io.BufferedWriter(4096, WrapStream) = undefined,

// Wraper around normal stream and tls stream
pub const WrapStream = struct {
    tls: ?tls.Client = null,
    stream: net.Stream,

    pub const Error = io.AnyReader.Error || io.AnyWriter.Error;

    pub fn read(self: WrapStream, buff: []u8) Error!usize {
        if (self.tls != null) {
            var tls_client = self.tls.?;
            return tls_client.read(self.stream, buff);
        }
        return self.stream.read(buff);
    }

    pub fn write(self: WrapStream, buff: []const u8) Error!usize {
        if (self.tls != null) {
            var tls_client = self.tls.?;
            return tls_client.write(self.stream, buff);
        }
        return self.stream.write(buff);
    }

    pub fn writeAll(self: WrapStream, buff: []const u8) Error!void {
        var index: usize = 0;
        while (index != buff.len) {
            index += try self.write(buff[index..]);
        }
    }
};

// connect to the IRC server and register to it
pub fn init(ally: std.mem.Allocator, config: anytype) !IRC {
    const stream = try net.tcpConnectToHost(ally, config.hostname, config.port);
    if (config.tls) {
        const bundle = try ally.create(std.crypto.Certificate.Bundle);
        bundle.* = .{};
        errdefer ally.destroy(bundle);
        try bundle.rescan(ally);
        errdefer bundle.deinit(ally);
        const tls_client = try tls.Client.init(stream, bundle.*, config.hostname);

        var irc = IRC{
            .stream = stream,
            .ally = ally,
            .bundle = bundle,
            .breader = io.bufferedReader(WrapStream{ .stream = stream, .tls = tls_client }),
            .bwriter = io.bufferedWriter(WrapStream{ .stream = stream, .tls = tls_client }),
        };
        try irc.handshake(config.nick, config.user);
        return irc;
    } else {
        var irc = IRC{
            .stream = stream,
            .ally = ally,
            .breader = io.bufferedReader(WrapStream{ .stream = stream, .tls = null }),
            .bwriter = io.bufferedWriter(WrapStream{ .stream = stream, .tls = null }),
        };
        try irc.handshake(config.nick, config.user);
        return irc;
    }
}

// close the connection to the IRC server
pub fn deinit(self: *IRC) void {
    if (self.bundle != null) self.bundle.?.deinit(self.ally);
    self.stream.close();
}

// register to the server
pub fn handshake(self: *IRC, nickname: []const u8, username: []const u8) !void {
    std.debug.print("{s}NICK {s}{s}\n", .{ colors.light_grey, nickname, colors.reset });
    try self.bwriter.writer().print("NICK {s}\n", .{nickname});
    std.debug.print("{s}USER {s} * * :Zig IRC Client{s}\n", .{ colors.light_grey, username, colors.reset });
    try self.bwriter.writer().print("USER {s} 0 * :Zig IRC Client\n", .{username});
    try self.bwriter.flush();
}

// get message from server and return them as Msg struct
// return null if couldnt parse message
pub fn eventLoop(self: *IRC, buffer: []u8) !struct { cmd: ?Cmd, len: usize } {
    while (true) {
        // will be freed by the root.recvMessageLoop
        const line = try self.breader.reader().readUntilDelimiter(buffer, '\n');
        // parse or show row
        const cmd = Cmd.parse(line) orelse return .{ .cmd = null, .len = line.len };
        // handling PING
        if (cmd.cmd == .ping) {
            try self.bwriter.writer().print("PONG {s}\n", .{cmd.cmd.ping.ping});
            try self.bwriter.flush();
        }
        return .{ .cmd = cmd, .len = line.len };
    }
}
