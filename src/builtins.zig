const std = @import("std");
const path = @import("path.zig");

pub const Builtin = enum { echo, type, exit, pwd, cd };

pub const BuiltinContext = struct {
    allocator: std.mem.Allocator,
    args: []const []const u8,
    path_dirs: []const []const u8,
    stdout: *std.Io.Writer,
};

pub const BuiltinResult = enum { continue_loop, exit_loop };

pub fn parseBuiltin(command: []const u8) ?Builtin {
    return std.meta.stringToEnum(Builtin, command);
}

pub fn executeBuiltin(builtin: Builtin, context: BuiltinContext) !BuiltinResult {
    switch (builtin) {
        .echo => {
            try doEcho(context);
            return .continue_loop;
        },
        .pwd => {
            try doPwd(context);
            return .continue_loop;
        },
        .cd => {
            try doCd(context);
            return .continue_loop;
        },
        .type => {
            try doType(context);
            return .continue_loop;
        },
        .exit => {
            return .exit_loop;
        },
    }
}

pub fn doEcho(context: BuiltinContext) !void {
    for (context.args, 0..) |arg, i| {
        if (i > 0) {
            try context.stdout.print(" ", .{});
        }
        try context.stdout.print("{s}", .{arg});
    }
    try context.stdout.print("\n", .{});
}

pub fn doPwd(context: BuiltinContext) !void {
    const pwd = try std.fs.cwd().realpathAlloc(context.allocator, ".");
    try context.stdout.print("{s}\n", .{pwd});
}

pub fn doCd(context: BuiltinContext) !void {
    if (context.args.len == 0) {
        try changeDir(context.stdout, "/home");
    } else if (std.mem.eql(u8, "~", context.args[0])) {
        const homeEnvVar = try path.getEnvVar(context.allocator, "HOME");
        defer context.allocator.free(homeEnvVar);
        try changeDir(context.stdout, homeEnvVar);
    } else {
        try changeDir(context.stdout, context.args[0]);
    }
}

pub fn doType(context: BuiltinContext) !void {
    if (context.args.len > 0) {
        if (std.meta.stringToEnum(Builtin, context.args[0]) != null) {
            try context.stdout.print("{s} is a shell builtin\n", .{context.args[0]});
        } else {
            const type_response = try typeCmd(context.allocator, context.args[0], context.path_dirs);
            try context.stdout.print("{s}\n", .{type_response});
        }
    }
}

fn typeCmd(allocator: std.mem.Allocator, cmd: []const u8, dirs: []const []const u8) ![]const u8 {
    if (try findCommandDir(allocator, dirs, cmd)) |dir| {
        return try std.mem.concat(allocator, u8, &[_][]const u8{ cmd, " is ", dir, "/", cmd });
    } else {
        return try std.mem.concat(allocator, u8, &[_][]const u8{ cmd, ": not found" });
    }
}

pub fn findCommandDir(allocator: std.mem.Allocator, dirs: []const []const u8, cmd: []const u8) !?[]const u8 {
    for (dirs) |dir| {
        // Check dir contents to look for command
        var iter_dir = std.fs.cwd().openDir(
            dir,
            .{ .iterate = true },
        ) catch |err| switch (err) {
            error.FileNotFound,
            error.NotDir,
            error.AccessDenied,
            error.PermissionDenied,
            => continue,
            else => return err,
        };
        defer {
            iter_dir.close();
        }
        var iter = iter_dir.iterate();
        while (try iter.next()) |entry| {
            if (std.mem.eql(u8, entry.name, cmd) and try fileHasExecutePermissions(allocator, dir, entry.name)) {
                return dir;
            }
        }
    }

    return null;
}

fn fileHasExecutePermissions(allocator: std.mem.Allocator, dir: []const u8, file: []const u8) !bool {
    const file_path = try std.mem.concat(allocator, u8, &[_][]const u8{ dir, "/", file });

    const cwd = std.fs.cwd();
    const open_file = cwd.openFile(file_path, .{ .mode = .read_only }) catch {
        return false;
    };

    defer open_file.close();

    const stat = try open_file.stat();
    return stat.mode & 0o100 != 0 or stat.mode & 0o010 != 0 or stat.mode & 0o001 != 0;
}

fn changeDir(stdout: *std.Io.Writer, newDir: []const u8) !void {
    var dir = std.fs.cwd().openDir(newDir, .{}) catch |err| {
        switch (err) {
            error.FileNotFound,
            error.NotDir,
            error.AccessDenied,
            error.PermissionDenied,
            => try stdout.print("cd: {s}: No such file or directory\n", .{newDir}),
            else => return err,
        }
        return;
    };

    defer dir.close();

    dir.setAsCwd() catch |err| switch (err) {
        error.NotDir,
        error.AccessDenied,
        => try stdout.print("\ncd: {s}: No such file or directory\n", .{newDir}),
        else => return err,
    };
}
