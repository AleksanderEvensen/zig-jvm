const std = @import("std");
const ClassFile = @import("./classfile.zig").ClassFile;

pub fn main() !void {
    std.debug.print("Opening file\n", .{});
    const file = try std.fs.cwd().openFile("./java-out/Main.class", .{});
    defer file.close();

    std.debug.print("Initializing reader\n", .{});
    const reader = file.reader();

    std.debug.print("Reading ClassFile\n\n", .{});
    var classFile = try ClassFile.fromReader(reader.any());
    std.debug.print("\n\n", .{});
    classFile.print();
}
