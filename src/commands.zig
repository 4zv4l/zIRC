const std = @import("std");
const io = std.io;
const fmt = std.fmt;
const mem = std.mem;
const net = std.net;
const log = std.log;
const IRC = @import("IRC");

pub const Cmd = struct {
    who: ?[]const u8,
    raw: []const u8,

    cmd: union(enum) {
        others: void, // command not here
        // PING <server1>
        ping: struct { ping: []const u8 },
        // USER <user> <mode> <unused> :<realname>
        user: struct {
            user: []const u8,
            mode: []const u8 = "0",
            unused: []const u8 = "*",
            realname: []const u8 = ":Zig IRC Client",
        },
        // NICK <nickname>
        nick: struct { nickname: []const u8 },
        // PRIVMSG <msgtarget> :<message>
        privmsg: struct { target: []const u8, msg: []const u8 },
        // LIST [<channels>]
        list: struct { channel: ?[]const u8 },
        // JOIN <channel>
        join: struct { channel: []const u8 },
        // PART <channel> [<message>]
        part: struct { channel: []const u8, msg: ?[]const u8 },
    },

    // raw command to Cmd
    pub fn parse(line: []u8) Cmd {
        var result: Cmd = undefined;
        result.who = null;
        result.raw = line;
        result.cmd = .others;

        if (mem.startsWith(u8, line, "PING")) {
            result.cmd = .{ .ping = .{ .ping = line[5..] } };
            return result;
        }

        if (line[0] == ':') {
            const username = line[1 .. mem.indexOfScalar(u8, line, '!') orelse 3];
            result.who = username;
            var space_it = mem.splitScalar(u8, line, ' ');
            _ = space_it.next() orelse return result;
            const cmd = blk: {
                const cmd = @constCast(space_it.next() orelse "?????");
                _ = std.ascii.lowerString(cmd, cmd);
                break :blk cmd;
            };

            if (mem.eql(u8, "privmsg", cmd)) {
                result.cmd = .{ .privmsg = .{
                    .target = space_it.next() orelse "???",
                    .msg = space_it.rest()[1..],
                } };
                return result;
            }
        }

        return result;
    }

    const colors = .{
        .light_grey = "\x1b[38;5;8m",
        .light_red = "\x1b[38;5;1m",
        .reset = "\x1b[0m",
    };

    pub fn format(
        self: Cmd,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self.cmd) {
            .ping => |p| {
                try writer.print("\r{s}PING {s}{s}\n", .{ colors.light_grey, p.ping, colors.reset });
                try writer.print("\r{s}PONG {s}{s}\n", .{ colors.light_grey, p.ping, colors.reset });
            },
            .privmsg => |m| {
                try writer.print("\r{s: >15} to {s} :: {s}\n", .{ self.who.?, m.target, m.msg });
            },
            else => {
                log.debug("\r{s}{s}b{s}", .{ colors.light_red, self.raw, colors.reset });
            },
        }
    }
};
