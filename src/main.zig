const std = @import("std");
const java_parser = @import("java-parser");

const classfile = java_parser.classfile;
const ClassFileReader = classfile.ClassFileReader;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    std.debug.print("Opening file\n", .{});
    const file = try std.fs.cwd().openFile("./java-out/Main.class", .{});
    defer file.close();

    std.debug.print("Initializing reader\n", .{});
    const reader = file.reader();

    std.debug.print("Reading ClassFile\n\n", .{});

    var classReader = ClassFileReader().init(allocator);
    const classFile = try classReader.read(reader.any());

    std.debug.print("\n\n", .{});
    classFile.printStruct(arena.allocator());
}
