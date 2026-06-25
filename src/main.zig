// TODO: Refactor into multiple files:
const parser = @import("parser.zig");
const builtins = @import("builtins.zig");
const path = @import("path.zig");
const std = @import("std");
const fmt = std.fmt;

var stdin_buffer: [4096]u8 = undefined;
var stdin_reader = std.fs.File.stdin().readerStreaming(&stdin_buffer);
const stdin = &stdin_reader.interface;

var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
const stdout = &stdout_writer.interface;

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = general_purpose_allocator.deinit();

    const allocator = general_purpose_allocator.allocator();

    const _path = try path.getPath(allocator);
    defer allocator.free(_path);

    var dirs: std.ArrayList([]const u8) = .empty;
    defer dirs.deinit(allocator);

    var dir_iterator = std.mem.splitScalar(u8, _path, ':');
    while (dir_iterator.next()) |dir| {
        if (dir.len == 0) continue;
        try dirs.append(allocator, dir);
    }

    var shouldLoop = true;
    while (shouldLoop) {
        try stdout.print("$ ", .{});
        try stdout.flush();
        const bare_line = try stdin.takeDelimiter('\n') orelse unreachable;
        const shellParser: parser.Parser = try parser.Parser.init(allocator, bare_line);
        defer shellParser.deinit(allocator);
        const command = shellParser.command;
        const args = shellParser.args;

        const builtinContext = builtins.BuiltinContext{
            .args = args,
            .allocator = allocator,
            .stdout = stdout,
            .path_dirs = dirs.items,
        };

        if (builtins.parseBuiltin(command)) |builtin| {
            const builtinResult = try builtins.executeBuiltin(builtin, builtinContext);

            if (builtinResult == .exit_loop) {
                shouldLoop = false;
                break;
            } else {
                continue;
            }
        } else {
            const command_dir = try builtins.findCommandDir(allocator, dirs.items, command);

            if (command_dir) |dir| {
                const command_path = try std.mem.concat(allocator, u8, &[_][]const u8{ dir, "/", command });
                defer allocator.free(command_path);

                var command_arguments: std.ArrayList([]const u8) = .empty;
                defer command_arguments.deinit(allocator);

                try command_arguments.append(allocator, command);
                for (args) |arg| {
                    try command_arguments.append(allocator, arg);
                }
                const result = try std.process.Child.run(.{
                    .allocator = allocator,
                    .argv = command_arguments.items,
                });
                defer allocator.free(result.stdout);
                defer allocator.free(result.stderr);

                if (result.stderr.len > 0) {
                    try stdout.print("{s}\n", .{result.stderr});
                } else {
                    if (result.stdout.len > 0 and
                        !std.mem.eql(u8, result.stdout, "\n") and
                        !std.mem.endsWith(u8, result.stdout, "\n"))
                    {
                        try stdout.print("{s}\n", .{result.stdout});
                    } else {
                        try stdout.print("{s}", .{result.stdout});
                    }
                }
            } else {
                try stdout.print("{s}: command not found\n", .{command});
            }
        }
    }
}
