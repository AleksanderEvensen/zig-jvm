const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

pub fn ClassFileReader() type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,

        constant_pool: ?[*]ConstantPoolEntry,

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .constant_pool = null,
            };
        }

        pub fn read(self: *Self, reader: std.io.AnyReader) !ClassFile {
            return ClassFile{
                .magic = try reader.readInt(u32, .big),
                .minor_version = try reader.readInt(u16, .big),
                .major_version = try reader.readInt(u16, .big),
                .constant_pool = try self.readConstantPool(reader),
                .access_flags = try reader.readInt(u16, .big),
                .this_class = try self.readThisClass(reader),
                .super_class = try self.readSuperClass(reader),
                .interfaces = try self.readBytes(reader, @intCast(try reader.readInt(u16, .big))), // TODO: Replace with readInterfaces
                .fields = try self.readBytes(reader, @intCast(try reader.readInt(u16, .big))), // TODO: Replace with readFields
                .methods = try self.readMethods(reader),
                .attributes = try self.readAttributes(reader),
            };
        }

        fn readConstantPool(self: *Self, reader: std.io.AnyReader) ![]ConstantPoolEntry {
            const cp_count: usize = @intCast(try reader.readInt(u16, .big) - 1);

            var constant_pool: []ConstantPoolEntry = try self.allocator.alloc(ConstantPoolEntry, cp_count);

            for (0..cp_count) |i| {
                const tag: ConstantPoolTag = @enumFromInt(try reader.readInt(u8, .big));

                switch (tag) {
                    ConstantPoolTag.Class => constant_pool[i] = ConstantPoolEntry{
                        .Class = try reader.readStructEndian(CP_Class, .big),
                    },

                    ConstantPoolTag.MethodRef => constant_pool[i] = ConstantPoolEntry{ .MethodRef = .{
                        .class_index = try reader.readInt(u16, .big),
                        .name_and_type_index = try reader.readInt(u16, .big),
                    } },

                    ConstantPoolTag.NameAndType => constant_pool[i] = ConstantPoolEntry{ .NameAndType = .{
                        .name_index = try reader.readInt(u16, .big),
                        .descriptor_index = try reader.readInt(u16, .big),
                    } },

                    ConstantPoolTag.Utf8 => constant_pool[i] = ConstantPoolEntry{ .Utf8 = .{
                        .bytes = try self.readBytes(reader, try reader.readInt(u16, .big)),
                    } },
                }
            }

            self.constant_pool = constant_pool.ptr;
            return constant_pool;
        }

        fn readThisClass(self: *Self, reader: std.io.AnyReader) !CP_Class {
            // TODO: Replace with error handling
            const cp = self.constant_pool orelse std.debug.panic("Failed to read #this_class: Constant pool is not initialized", .{});
            const this_class_index = try reader.readInt(u16, .big);

            return cp[this_class_index - 1].Class;
        }

        fn readSuperClass(self: *Self, reader: std.io.AnyReader) !CP_Class {
            // TODO: Replace with error handling
            const cp = self.constant_pool orelse std.debug.panic("Failed to read #super_class: Constant pool is not initialized", .{});

            const super_class_index = try reader.readInt(u16, .big);
            return cp[super_class_index - 1].Class;
        }

        fn readMethods(self: *Self, reader: std.io.AnyReader) ![]MethodInfo {
            const method_count = try reader.readInt(u16, .big);

            var methods = try self.allocator.alloc(MethodInfo, method_count);

            for (0..method_count) |i| {
                methods[i] = MethodInfo{
                    .access_flags = try reader.readInt(u16, .big),
                    .name_index = try reader.readInt(u16, .big),
                    .descriptor_index = try reader.readInt(u16, .big),
                    .attributes = try self.readAttributes(reader),
                };
            }

            return methods;
        }

        fn readAttributes(self: *Self, reader: std.io.AnyReader) ![]AttributeInfo {
            const cp = self.constant_pool orelse std.debug.panic("Failed to read AttributeInfo: Constant Pool is not initialized", .{});

            const attrib_count: usize = @intCast(try reader.readInt(u16, .big));
            const attributes: []AttributeInfo = try self.allocator.alloc(AttributeInfo, attrib_count);

            for (0..attrib_count) |i| {
                const name = cp[try reader.readInt(u16, .big) - 1].Utf8.bytes;

                // Attribute length
                _ = try reader.readInt(u32, .big);

                const attributeTag = std.meta.stringToEnum(AttributeInfoTag, name) orelse {
                    std.debug.print("Unrecognized attribute '{s}' \n", .{name});
                    unreachable;
                };

                switch (attributeTag) {
                    AttributeInfoTag.Code => {
                        const max_stack = try reader.readInt(u16, .big);
                        const max_locals = try reader.readInt(u16, .big);
                        const code_length = try reader.readInt(u32, .big);
                        const code = try self.readBytes(reader, code_length);
                        const exception_table = try self.readBytes(reader, try reader.readInt(u16, .big) * 8);
                        const code_attributes = try self.readAttributes(reader);

                        attributes[i] = AttributeInfo{
                            .Code = Attrib_Code{
                                .max_stack = max_stack,
                                .max_locals = max_locals,
                                .code = code,
                                .exception_table = exception_table,
                                .attributes = code_attributes,
                            },
                        };
                    },

                    AttributeInfoTag.LineNumberTable => {
                        const table_length = try reader.readInt(u16, .big);
                        const table = try std.heap.page_allocator.alloc(Attrib_LineNumberTable, table_length);

                        var j: usize = 0;
                        while (j < table_length) : (j += 1) {
                            table[j] = Attrib_LineNumberTable{
                                .start_pc = try reader.readInt(u16, .big),
                                .line_number = try reader.readInt(u16, .big),
                            };
                        }

                        attributes[i] = AttributeInfo{
                            .LineNumberTable = table,
                        };
                    },

                    AttributeInfoTag.SourceFile => {
                        attributes[i] = AttributeInfo{
                            .SourceFile = Attrib_SourceFile{
                                .sourcefile_index = try reader.readInt(u16, .big),
                            },
                        };
                    },

                    else => {
                        std.debug.print("Unimplemented attribute '{s}'\n", .{name});
                        unreachable;
                    },
                }
            }

            return attributes;
        }

        fn readBytes(self: *Self, reader: std.io.AnyReader, len: usize) ![]u8 {
            if (len == 0) {
                return undefined;
            }
            const buffer: []u8 = try self.allocator.alloc(u8, len);
            _ = try reader.readAtLeast(buffer, len);
            return buffer;
        }
    };
}

pub const ClassFile = struct {
    magic: u32,
    minor_version: u16,
    major_version: u16,
    constant_pool: []ConstantPoolEntry,
    access_flags: u16,
    this_class: CP_Class,
    super_class: CP_Class,
    interfaces: []u8,
    fields: []u8,
    methods: []MethodInfo,
    attributes: []AttributeInfo,

    pub fn printStruct(self: ClassFile, alloc: std.mem.Allocator) void {
        print(
            \\Magic: 0x{X:0>8}
            \\Version: {}.{}
            \\This Class: #{} '{s}'
            \\Super Class: #{} '{s}'
            \\
        , .{
            self.magic,
            self.major_version,
            self.minor_version,

            self.this_class.name_index,
            self.constant_pool[self.this_class.name_index - 1].Utf8.bytes,

            self.super_class.name_index,
            self.constant_pool[self.super_class.name_index - 1].Utf8.bytes,
        });

        print("Constant Pool({}):\n", .{self.constant_pool.len});
        for (self.constant_pool, 1..) |cp_info, i| {
            print("  #{}: {s}\n", .{ i, cp_info.toString(self.constant_pool, alloc) });
        }

        print("Methods({}):\n", .{self.methods.len});
        for (self.methods, 1..) |method, i| {
            std.debug.print("  #{}: {s}:{s}\n", .{ i, self.constant_pool[method.name_index - 1].Utf8.bytes, self.constant_pool[method.descriptor_index - 1].Utf8.bytes });
            for (method.attributes) |attrib| {
                switch (attrib) {
                    AttributeInfo.ConstantValue => std.debug.print("    ConstantValue\n", .{}),
                    AttributeInfo.Code => {
                        const code = attrib.Code;
                        print(
                            \\    Code\n
                            \\      Max Stack: {}
                            \\      Max Locals: {}
                            \\      Code Length: {}
                            \\      Instructions:
                            \\        {any}
                            \\
                        , .{ code.max_stack, code.max_locals, code.code.len, code.code });
                    },
                    AttributeInfo.Exceptions => std.debug.print("    Exceptions\n", .{}),
                    AttributeInfo.SourceFile => std.debug.print("    SourceFile\n", .{}),
                    AttributeInfo.LineNumberTable => {
                        const table = attrib.LineNumberTable;
                        std.debug.print("    LineNumberTable({}):\n", .{table.len});
                        for (table) |line| {
                            std.debug.print("      Start PC: {}, Line Number: {}\n", .{ line.start_pc, line.line_number });
                        }
                    },
                }
            }
        }
    }
};

const ConstantPoolTag = enum(u8) {
    Class = 7,
    // FieldRef = 9,
    MethodRef = 10,
    // InterfaceMethodRef = 11,
    // String = 8,
    // Integer = 3,
    // Float = 4,
    // Long = 5,
    // Double = 6,
    NameAndType = 12,
    Utf8 = 1,
    // MethodHandle = 15,
    // MethodType = 16,
    // Dynamic = 17,
    // Module = 19,
    // Package = 20,
};

const ConstantPoolEntry = union(ConstantPoolTag) {
    Class: CP_Class,
    MethodRef: CP_MethodRef,
    NameAndType: CP_NameAndType,
    Utf8: CP_Utf8,

    fn toString(self: ConstantPoolEntry, cp: []ConstantPoolEntry, alloc: std.mem.Allocator) []u8 {
        switch (self) {
            ConstantPoolEntry.Class => {
                const name = cp[self.Class.name_index - 1].Utf8.bytes;
                return std.fmt.allocPrint(alloc, "Class: #{} '{s}'", .{ self.Class.name_index, name }) catch {
                    unreachable;
                };
            },
            ConstantPoolEntry.MethodRef => {
                const class = cp[self.MethodRef.class_index - 1].Class;
                const nameAndType = cp[self.MethodRef.name_and_type_index - 1].NameAndType;
                const className = cp[class.name_index - 1].Utf8.bytes;
                const name = cp[nameAndType.name_index - 1].Utf8.bytes;
                const descriptor = cp[nameAndType.descriptor_index - 1].Utf8.bytes;
                return std.fmt.allocPrint(alloc, "MethodRef: #{}.#{} '{s}.{s}:{s}'", .{ self.MethodRef.class_index, self.MethodRef.name_and_type_index, className, name, descriptor }) catch {
                    unreachable;
                };
            },
            ConstantPoolEntry.NameAndType => {
                const name = cp[self.NameAndType.name_index - 1].Utf8.bytes;
                const descriptor = cp[self.NameAndType.descriptor_index - 1].Utf8.bytes;
                return std.fmt.allocPrint(alloc, "NameAndType: #{}.#{} '{s}:{s}'", .{ self.NameAndType.name_index, self.NameAndType.descriptor_index, name, descriptor }) catch {
                    unreachable;
                };
            },
            ConstantPoolEntry.Utf8 => {
                return std.fmt.allocPrint(alloc, "Utf8: '{s}'", .{self.Utf8.bytes}) catch {
                    unreachable;
                };
            },
        }
    }
};

const CP_Class = packed struct {
    name_index: u16,
};

const CP_MethodRef = packed struct {
    class_index: u16,
    name_and_type_index: u16,

    fn getClassName(self: CP_MethodRef, cp: []ConstantPoolEntry) ![]u8 {
        return cp[cp[self.class_index - 1].Class.name_index - 1].Utf8.bytes;
    }
};

const CP_NameAndType = packed struct {
    name_index: u16,
    descriptor_index: u16,
};

const CP_Utf8 = struct {
    bytes: []u8,
};

const MethodInfo = struct {
    access_flags: u16,
    name_index: u16,
    descriptor_index: u16,
    attributes: []AttributeInfo,
};

const AttributeInfoTag = enum(u8) {
    ConstantValue = 0,
    Code = 1,
    Exceptions = 2,
    SourceFile = 3,
    LineNumberTable = 4,
};

const AttributeInfo = union(AttributeInfoTag) {
    ConstantValue: Attrib_ConstantValue,
    Code: Attrib_Code,
    Exceptions: Attrib_Exceptions,
    SourceFile: Attrib_SourceFile,
    LineNumberTable: []Attrib_LineNumberTable,
};

const Attrib_ConstantValue = struct {};
const Attrib_Code = struct {
    max_stack: u16,
    max_locals: u16,
    code: []u8,
    exception_table: []u8, // TODO: Change from u8 to the actual struct
    attributes: []AttributeInfo,
};
const Attrib_Exceptions = struct {};
const Attrib_SourceFile = struct {
    sourcefile_index: u16,
};
const Attrib_LineNumberTable = struct {
    start_pc: u16,
    line_number: u16,
};
