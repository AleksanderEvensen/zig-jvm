const std = @import("std");
const java_parser = @import("java-parser");
const java_vm = @import("java-vm");

const classfile = java_parser.classfile;
const ClassFileReader = classfile.ClassFileReader;
const VirtualMachine = java_vm.VirtualMachine;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    std.debug.print("Reading class files...\n", .{});
    const mainClass = try loadClassFile("./java-out/Main.class", arena.allocator());
    // const printStreamClass = try loadClassFile("./java-runtime/java.base/java/io/PrintStream.class", arena.allocator());
    // const systemClass = try loadClassFile("./java-runtime/java.base/java/lang/System.class", arena.allocator());

    std.debug.print("\n\n", .{});
    mainClass.printStruct(arena.allocator());

    var vm = VirtualMachine().init(allocator);
    // try vm.addClass(systemClass);
    // try vm.addClass(printStreamClass);
    try vm.addClass(mainClass);

    // try vm.run();
}

fn loadClassFile(path: []const u8, allocator: std.mem.Allocator) !classfile.ClassFile {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const reader = file.reader();

    var classReader = ClassFileReader().init(allocator);
    return try classReader.read(reader.any());
}
