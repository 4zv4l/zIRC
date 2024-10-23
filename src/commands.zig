const std = @import("std");
const mem = std.mem;
const Colors = @import("colors.zig").colors;

pub const Cmd = struct {
    who: ?[]const u8,
    raw: []const u8,

    cmd: union(enum) {
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
        // QUIT
        quit: struct { reason: []const u8 },
    },

    // raw command to Cmd
    pub fn parse(line: []u8) ?Cmd {
        var result: Cmd = undefined;
        result.raw = line;

        if (mem.startsWith(u8, line, "PING")) {
            result.cmd = .{ .ping = .{ .ping = line[5..] } };
            return result;
        }

        if (line[0] == ':') {
            var space_it = mem.splitScalar(u8, line, ' ');

            // parse host sending command
            const who = if (space_it.next()) |who| who else return null;
            const length = mem.indexOfScalar(u8, who, '!') orelse who.len;
            result.who = who[1..length]; // skip :

            // parse command
            const cmd = blk: {
                const cmd = @constCast(space_it.next() orelse return null);
                _ = std.ascii.lowerString(cmd, cmd);
                break :blk cmd;
            };

            // parse arguments depending on the command
            if (mem.eql(u8, "privmsg", cmd)) {
                result.cmd = .{
                    .privmsg = .{
                        .target = space_it.next() orelse return null,
                        .msg = space_it.rest()[1..], // skip :
                    },
                };
                return result;
            } else if (mem.eql(u8, "quit", cmd)) {
                result.cmd = .{ .quit = .{ .reason = space_it.rest()[1..] } };
                return result;
            } else if (mem.eql(u8, "join", cmd)) {
                result.cmd = .{ .join = .{ .channel = space_it.rest()[1..] } };
                return result;
            } else if (mem.eql(u8, "part", cmd)) {
                result.cmd = .{ .part = .{ .channel = space_it.next().?, .msg = space_it.rest()[1..] } };
                return result;
            }
        }

        return null;
    }

    pub fn format(
        self: Cmd,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self.cmd) {
            .ping => |p| {
                try writer.print("{0s}PING {1s}\nPONG {1s}{2s}", .{ Colors.light_grey, p.ping, Colors.reset });
            },
            .privmsg => |m| {
                try writer.print("{s: >15} to {s} :: {s}", .{ self.who.?, m.target, m.msg });
            },
            .join => |j| {
                try writer.print("{s: >15} joined {s}", .{ self.who.?, j.channel });
            },
            .quit => |q| {
                try writer.print("{s: >15} quit {s}", .{ self.who.?, q.reason });
            },
            .part => |p| {
                try writer.print("{s: >15} part {s} {s}", .{ self.who.?, p.channel, p.msg orelse "" });
            },
            else => {
                try writer.print("{s}{s}{s}", .{ Colors.light_red, self.raw, Colors.reset });
            },
        }
    }
};
