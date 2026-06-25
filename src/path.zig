const std = @import("std");

pub fn getPath(allocator: std.mem.Allocator) ![]const u8 {
    return try getEnvVar(allocator, "PATH");
}

pub fn getEnvVar(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const value = std.process.getEnvVarOwned(allocator, name);
    return value;
}
