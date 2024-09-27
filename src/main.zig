const std = @import("std");

pub fn main() !void {
    const file = try std.fs.cwd().openFile(
        "",
        .{ .read = true },
    );
}
