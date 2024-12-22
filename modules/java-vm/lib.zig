const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

const java_parser = @import("java-parser");
const classfile = java_parser.classfile;
const opcodes = java_parser.opcodes;
const ClassFile = classfile.ClassFile;
const OpCodeTag = opcodes.OpCodeTag;

pub fn VirtualMachine() type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        classFiles: std.StringHashMap(ClassFile),

        mainMethod: ?struct { class: ClassFile, methodIndex: usize },

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .classFiles = std.StringHashMap(ClassFile).init(allocator),

                .mainMethod = null,
            };
        }

        pub fn addClass(self: *Self, classFile: ClassFile) !void {
            const name = classFile.this_class.name;
            const entry = try self.classFiles.getOrPut(name);
            entry.value_ptr.* = classFile;

            for (classFile.methods, 0..) |method, i| {
                if (!std.mem.eql(u8, method.name, "main")) continue;
                if (@as(u16, @bitCast(method.access_flags)) != @as(u16, 9)) continue; // public, static
                self.mainMethod = .{ .class = classFile, .methodIndex = i };
            }
        }

        pub fn run(self: *Self) !void {
            if (self.mainMethod) |main_method| {
                const method = main_method.class.methods[main_method.methodIndex];
                try self.runMethod(main_method.class, method);
            } else {
                print("No main method found\n", .{});
            }
        }

        fn runMethod(self: *Self, current_class: ClassFile, method: classfile.MethodInfo) !void {
            print("Running method: {s}\n", .{method.name});

            const code_attrib: ?classfile.Attrib_Code = find_code: for (method.attributes) |attribute| {
                switch (attribute) {
                    classfile.AttributeInfoTag.Code => |code| break :find_code code,
                    else => continue,
                }
            } else null;

            if (code_attrib) |code| {
                print("Max Locals: {d}\n", .{code.max_locals});
                print("Max Stack: {d}\n", .{code.max_stack});
                var stack = try std.ArrayList(StackValue).initCapacity(self.allocator, code.max_stack);
                defer stack.deinit();
                var locals = try self.allocator.alloc(StackValue, code.max_locals);
                defer self.allocator.free(locals);

                for (code.code) |instruction| {
                    try switch (instruction) {
                        OpCodeTag.iconst_0 => stack.append(.{ .Int = 0 }),

                        OpCodeTag.istore_1 => {
                            const stack_value = stack.pop();
                            assert(stack_value == .Int);
                            locals[1] = stack_value;
                        },
                        OpCodeTag.istore_2 => {
                            const stack_value = stack.pop();
                            assert(stack_value == .Int);
                            locals[2] = stack_value;
                        },
                        OpCodeTag.istore_3 => {
                            const stack_value = stack.pop();
                            assert(stack_value == .Int);
                            locals[3] = stack_value;
                        },

                        OpCodeTag.iload_1 => {
                            assert(locals[1] == .Int);
                            try stack.append(locals[1]);
                        },
                        OpCodeTag.iload_2 => {
                            assert(locals[2] == .Int);
                            try stack.append(locals[2]);
                        },

                        OpCodeTag.iadd => {
                            const a = stack.pop();
                            const b = stack.pop();
                            assert(a == .Int and b == .Int);
                            try stack.append(.{ .Int = a.Int + b.Int });
                        },

                        .getstatic => |data| {
                            const cp = current_class.constant_pool[data.index - 1];
                            assert(cp == .FieldRef);
                            const class = cp.FieldRef.class;
                            const name = cp.FieldRef.name_and_type;

                            const class_name = class.name;
                            const field_name = name.name;
                            const field_descriptor = name.descriptor;
                            // TODO: Check this one out later
                            // TODO: implement class initialization logic if class isn't previously initialized
                            try stack.append(.{
                                .StaticField = .{
                                    .class_name = class_name,
                                    .field_name = field_name,
                                    .field_descriptor = field_descriptor,
                                },
                            });

                            print(
                                \\Instruction getstatic:
                                \\  Class Name: {s}
                                \\  Field Name: {s}
                                \\  Field Descriptor: {s}
                                \\
                            , .{ class_name, field_name, field_descriptor });
                        },

                        .bipush => |data| try stack.append(.{ .Byte = data.byte }),

                        .invokevirtual => |data| {
                            const cp = current_class.constant_pool[data.index - 1];
                            assert(cp == .MethodRef);
                            const ref = cp.MethodRef;
                            print(
                                \\Instruction invokevirtual:
                                \\  Class Name: {s}
                                \\  Name And Type: {s}{s}
                                \\
                            , .{
                                ref.class.name,
                                ref.name_and_type.name,
                                ref.name_and_type.descriptor,
                            });
                        },

                        else => std.debug.panic("Runtime error:\n  Unimplemented instruction: {any}\n", .{instruction}),
                    };
                }
            } else {
                // TODO: Check this later. this might actually not be an error
                std.debug.panic("Tried to run a methods without code instructions\n", .{});
            }
        }
    };
}

const StackTag = enum {
    Int,
    Long,
    Float,
    Double,

    Byte,
    StaticField,
};
const StackValue = union(StackTag) {
    Int: i32,
    Long: i64,
    Float: f32,
    Double: f64,

    Byte: u8,
    StaticField: struct {
        class_name: []u8,
        field_name: []u8,
        field_descriptor: []u8,
    },
};
