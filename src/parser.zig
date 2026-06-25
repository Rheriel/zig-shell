const std = @import("std");

pub const Parser = struct {
    bare_line: []const u8,
    line: []const u8,
    command: []const u8,
    argv: []const u8,
    args: []const []const u8,

    fn parseArgs(allocator: std.mem.Allocator, args: []const u8) ![]const []const u8 {
        var result: std.ArrayList([]const u8) = .empty;
        var current_arg: std.ArrayList(u8) = .empty;
        defer result.deinit(allocator);
        defer current_arg.deinit(allocator);
        var in_single_quote = false;
        var in_double_quote = false;
        var started_argument = false;

        for (args) |c| {
            switch (c) {
                '\'' => if (!in_double_quote) {
                    started_argument = true;
                    in_single_quote = !in_single_quote;
                } else {
                    if (in_single_quote or in_double_quote) {
                        started_argument = true;
                        try current_arg.append(allocator, c);
                    }
                },
                '"' => if (!in_single_quote) {
                    started_argument = true;
                    in_double_quote = !in_double_quote;
                },
                ' ', '\t' => {
                    if (in_single_quote or in_double_quote) {
                        started_argument = true;
                        try current_arg.append(allocator, c);
                    } else {
                        if (started_argument) {
                            try result.append(allocator, try current_arg.toOwnedSlice(allocator));
                            current_arg = .empty;
                            started_argument = false;
                        }
                    }
                },
                else => {
                    started_argument = true;
                    try current_arg.append(allocator, c);
                },
            }
        }
        if (current_arg.items.len > 0) {
            try result.append(allocator, try current_arg.toOwnedSlice(allocator));
        }
        return try result.toOwnedSlice(allocator);
    }

    fn getCommand(line: []const u8) []const u8 {
        const firstSpaceIndex = std.mem.indexOfScalar(u8, line, ' ');

        if (firstSpaceIndex) |index| {
            return line[0..index];
        }

        return line;
    }

    fn getArgv(line: []const u8) []const u8 {
        const firstSpaceIndex = std.mem.indexOfScalar(u8, line, ' ');

        if (firstSpaceIndex) |index| {
            return line[index + 1 .. line.len];
        }

        return "";
    }

    pub fn init(allocator: std.mem.Allocator, bare_line: []const u8) !Parser {
        const line = std.mem.trim(u8, bare_line, "\r");
        const command = getCommand(line);
        const argv = getArgv(line);
        const args = try parseArgs(allocator, argv);

        return Parser{ .bare_line = bare_line, .line = line, .command = command, .argv = argv, .args = args };
    }

    pub fn deinit(self: *const Parser, allocator: std.mem.Allocator) void {
        for (self.args) |arg| allocator.free(arg);
        allocator.free(self.args);
    }
};
