const std = @import("std");
const opcodes = @import("./opcodes.zig");
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
                .access_flags = @bitCast(try reader.readInt(u16, .big)),
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

            const RawConstantPool = struct {
                tag: ConstantPoolTag,
                bytes: []u8,
                index: usize,
                initialzed: bool,
            };

            var raw_constant_pool = try std.ArrayList(RawConstantPool).initCapacity(self.allocator, cp_count);
            defer raw_constant_pool.deinit();
            var constant_pool = try self.allocator.alloc(ConstantPoolEntry, cp_count);

            for (0..cp_count) |i| {
                const tag_byte = try reader.readByte();
                const tag = std.meta.intToEnum(ConstantPoolTag, tag_byte) catch {
                    std.debug.panic("Unrecognized constant pool tag: {d}", .{tag_byte});
                };

                try raw_constant_pool.append(.{
                    .tag = tag,
                    .bytes = try self.readBytes(reader, switch (tag) {
                        .Class => 2,
                        .MethodRef, .FieldRef, .InterfaceMethodRef => 4,
                        .String => 2,
                        .NameAndType => 4,
                        .Utf8 => try reader.readInt(u16, .big),
                    }),
                    .index = i,
                    .initialzed = false,
                });
            }

            const CpInitializer = struct {
                const Dis = @This();

                pub fn init(
                    this: *Dis,
                    index: usize,
                    cp: *[]ConstantPoolEntry,
                    raw_cp: *std.ArrayList(RawConstantPool),
                ) *ConstantPoolEntry {
                    const raw = raw_cp.items[index - 1];
                    if (raw.initialzed) {
                        return &cp.*[index - 1];
                    }
                    raw_cp.items[index - 1].initialzed = true;

                    const readBE = struct {
                        pub fn inner(comptime T: type, bytes: *const [@divExact(@typeInfo(T).Int.bits, 8)]u8) T {
                            return std.mem.readInt(T, bytes, .big);
                        }
                    }.inner;

                    cp.*[index - 1] = switch (raw.tag) {
                        .Class => ConstantPoolEntry{
                            .Class = CP_Class{
                                .name_index = readBE(u16, raw.bytes[0..2]),
                                .name = this.init(readBE(u16, raw.bytes[0..2]), cp, raw_cp).*.Utf8,
                            },
                        },

                        .MethodRef => ConstantPoolEntry{
                            .MethodRef = .{
                                .class_index = readBE(u16, raw.bytes[0..2]),
                                .name_and_type_index = readBE(u16, raw.bytes[2..4]),
                                .class = &this.init(readBE(u16, raw.bytes[0..2]), cp, raw_cp).Class,
                                .name_and_type = &this.init(readBE(u16, raw.bytes[2..4]), cp, raw_cp).NameAndType,
                            },
                        },

                        .FieldRef => ConstantPoolEntry{
                            .FieldRef = .{
                                .class_index = readBE(u16, raw.bytes[0..2]),
                                .name_and_type_index = readBE(u16, raw.bytes[2..4]),
                                .class = &this.init(readBE(u16, raw.bytes[0..2]), cp, raw_cp).Class,
                                .name_and_type = &this.init(readBE(u16, raw.bytes[2..4]), cp, raw_cp).NameAndType,
                            },
                        },

                        .InterfaceMethodRef => ConstantPoolEntry{
                            .InterfaceMethodRef = .{
                                .class_index = readBE(u16, raw.bytes[0..2]),
                                .name_and_type_index = readBE(u16, raw.bytes[2..4]),
                                .class = &this.init(readBE(u16, raw.bytes[0..2]), cp, raw_cp).Class,
                                .name_and_type = &this.init(readBE(u16, raw.bytes[2..4]), cp, raw_cp).NameAndType,
                            },
                        },

                        .NameAndType => ConstantPoolEntry{
                            .NameAndType = .{
                                .name_index = readBE(u16, raw.bytes[0..2]),
                                .descriptor_index = readBE(u16, raw.bytes[2..4]),
                                .name = this.init(readBE(u16, raw.bytes[0..2]), cp, raw_cp).*.Utf8,
                                .descriptor = this.init(readBE(u16, raw.bytes[2..4]), cp, raw_cp).*.Utf8,
                            },
                        },

                        .Utf8 => ConstantPoolEntry{
                            .Utf8 = raw.bytes,
                        },

                        .String => ConstantPoolEntry{
                            .String = CP_String{
                                .string_index = readBE(u16, raw.bytes[0..2]),
                                .string = this.init(readBE(u16, raw.bytes[0..2]), cp, raw_cp).*.Utf8,
                            },
                        },
                    };
                    return &cp.*[index - 1];
                }
            };

            var initializer = CpInitializer{};
            for (0..cp_count) |i| {
                if (raw_constant_pool.items[i].initialzed) continue;

                _ = initializer.init(i + 1, &constant_pool, &raw_constant_pool);
            }

            for (0..constant_pool.len) |i| {
                switch (constant_pool[i]) {
                    .Class => |*v| v.*.name = constant_pool[v.*.name_index - 1].Utf8,
                    .MethodRef, .FieldRef, .InterfaceMethodRef => |*v| {
                        v.*.class = &constant_pool[v.*.class_index - 1].Class;
                        v.*.name_and_type = &constant_pool[v.*.name_and_type_index - 1].NameAndType;
                    },
                    .NameAndType => |*v| {
                        v.*.name = constant_pool[v.*.name_index - 1].Utf8;
                        v.*.descriptor = constant_pool[v.*.descriptor_index - 1].Utf8;
                    },
                    .String => |*v| v.*.string = constant_pool[v.*.string_index - 1].Utf8,

                    else => {},
                }
            }

            self.constant_pool = constant_pool.ptr;
            return constant_pool;
        }

        fn readThisClass(self: *Self, reader: std.io.AnyReader) !*CP_Class {
            // TODO: Replace with error handling
            const cp = self.constant_pool orelse std.debug.panic("Failed to read #this_class: Constant pool is not initialized", .{});
            const this_class_index = try reader.readInt(u16, .big);

            return &cp[this_class_index - 1].Class;
        }

        fn readSuperClass(self: *Self, reader: std.io.AnyReader) !*CP_Class {
            // TODO: Replace with error handling
            const cp = self.constant_pool orelse std.debug.panic("Failed to read #super_class: Constant pool is not initialized", .{});
            const super_class_index = try reader.readInt(u16, .big);

            return &cp[super_class_index - 1].Class;
        }

        fn readMethods(self: *Self, reader: std.io.AnyReader) ![]MethodInfo {
            const method_count = try reader.readInt(u16, .big);

            var methods = try self.allocator.alloc(MethodInfo, method_count);

            for (0..method_count) |i| {
                methods[i] = MethodInfo{
                    .access_flags = @bitCast(try reader.readInt(u16, .big)),
                    .name = self.constant_pool.?[try reader.readInt(u16, .big) - 1].Utf8,
                    .descriptor = self.constant_pool.?[try reader.readInt(u16, .big) - 1].Utf8,
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
                const name = cp[try reader.readInt(u16, .big) - 1].Utf8;

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
                        const code = try opcodes.parse_opcodes(try self.readBytes(reader, code_length), self.allocator);
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
    access_flags: packed struct(u16) {
        public: bool = false,
        _1: u3 = 0,
        final: bool = false,
        super: bool = false,
        _2: u3 = 0,
        interface: bool = false,
        abstract: bool = false,
        _5: u1 = 0,
        synthetic: bool = false,
        annotation: bool = false,
        _enum: bool = false,
        module: bool = false,
    },
    this_class: *CP_Class,
    super_class: *CP_Class,
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
            self.this_class.name,

            self.super_class.name_index,
            self.super_class.name,
        });

        print("Constant Pool({}):\n", .{self.constant_pool.len});

        for (self.constant_pool, 1..) |cp_info, i| {
            print("  #{}: {s}\n", .{ i, cp_info.toString(alloc) });
        }

        print("Methods({}):\n", .{self.methods.len});
        for (self.methods, 1..) |method, i| {
            print("  #{}: {s}:{s}\n", .{
                i,
                method.name,
                method.descriptor,
            });
            for (method.attributes) |attrib| {
                switch (attrib) {
                    AttributeInfo.ConstantValue => print("    ConstantValue\n", .{}),
                    AttributeInfo.Code => {
                        const code = attrib.Code;
                        print(
                            \\    Code
                            \\      Max Stack: {}
                            \\      Max Locals: {}
                            \\      Code Length: {}
                            \\      Instructions:
                            \\
                        , .{ code.max_stack, code.max_locals, code.code.len });

                        for (code.code, 0..) |op, code_i| {
                            print("        {d}: {s}\n", .{ code_i, op.toString(alloc) });
                        }
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

pub const ConstantPoolTag = enum(u8) {
    Class = 7,
    FieldRef = 9,
    MethodRef = 10,
    InterfaceMethodRef = 11,
    String = 8,
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

pub const ConstantPoolEntry = union(ConstantPoolTag) {
    Class: CP_Class,
    FieldRef: CP_Ref,
    MethodRef: CP_Ref,
    InterfaceMethodRef: CP_Ref,
    String: CP_String,
    NameAndType: CP_NameAndType,
    Utf8: []u8,

    fn toString(self: ConstantPoolEntry, alloc: std.mem.Allocator) []u8 {
        return switch (self) {
            ConstantPoolEntry.Class => |v| std.fmt.allocPrint(alloc, "Class: #{} '{s}'", .{
                v.name_index,
                v.name,
            }) catch unreachable,
            ConstantPoolEntry.MethodRef => |v| std.fmt.allocPrint(alloc, "MethodRef: #{}.#{} '{s}.{s}:{s}'", .{
                v.class_index,
                v.name_and_type_index,
                v.class.name,
                v.name_and_type.name,
                v.name_and_type.descriptor,
            }) catch unreachable,
            ConstantPoolEntry.NameAndType => |v| std.fmt.allocPrint(alloc, "NameAndType: #{}.#{} '{s}:{s}'", .{
                v.name_index,
                v.descriptor_index,
                v.name,
                v.descriptor,
            }) catch unreachable,
            ConstantPoolEntry.Utf8 => |str| std.fmt.allocPrint(alloc, "Utf8: '{s}'", .{str}) catch unreachable,
            ConstantPoolEntry.String => |v| std.fmt.allocPrint(alloc, "String: #{} '{s}'", .{ v.string_index, v.string }) catch unreachable,
            else => std.fmt.allocPrint(alloc, "Unknown: Unimplemented", .{}) catch unreachable,
        };
    }
};

pub const CP_Class = struct {
    name_index: u16,

    name: []u8,
};

pub const CP_Ref = struct {
    class_index: u16,
    name_and_type_index: u16,

    class: *CP_Class,
    name_and_type: *CP_NameAndType,
};

pub const CP_NameAndType = struct {
    name_index: u16,
    descriptor_index: u16,

    name: []u8,
    descriptor: []u8,
};

pub const CP_String = struct {
    string_index: u16,
    string: []u8,
};

pub const MethodInfo = struct {
    access_flags: MethodAccessFlags,
    name: []u8,
    descriptor: []u8,
    attributes: []AttributeInfo,
};

pub const MethodAccessFlags = packed struct(u16) {
    public: bool = false,
    private: bool = false,
    protected: bool = false,
    static: bool = false,
    final: bool = false,
    synchronized: bool = false,
    bridge: bool = false,
    varargs: bool = false,
    native: bool = false,
    _: u1 = 0,
    abstract: bool = false,
    strict: bool = false,
    synthetic: bool = false,
    _1: u3 = 0,
};

pub const AttributeInfoTag = enum(u8) {
    ConstantValue = 0,
    Code = 1,
    Exceptions = 2,
    SourceFile = 3,
    LineNumberTable = 4,
};

pub const AttributeInfo = union(AttributeInfoTag) {
    ConstantValue: Attrib_ConstantValue,
    Code: Attrib_Code,
    Exceptions: Attrib_Exceptions,
    SourceFile: Attrib_SourceFile,
    LineNumberTable: []Attrib_LineNumberTable,
};

pub const Attrib_ConstantValue = struct {};
pub const Attrib_Code = struct {
    max_stack: u16,
    max_locals: u16,
    code: []opcodes.OpCode,
    exception_table: []u8, // TODO: Change from u8 to the actual struct
    attributes: []AttributeInfo,
};
pub const Attrib_Exceptions = struct {};
pub const Attrib_SourceFile = struct {
    sourcefile_index: u16,
};
pub const Attrib_LineNumberTable = struct {
    start_pc: u16,
    line_number: u16,
};
