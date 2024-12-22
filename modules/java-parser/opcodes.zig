const std = @import("std");

pub const NoParams = packed struct {};

pub const OpCodeTag = enum(u8) {
    iconst_0 = 3,
    bipush = 16,
    iload_1 = 27,
    iload_2 = 28,
    iload_3 = 29,
    aload_0 = 42,
    istore_1 = 60,
    istore_2 = 61,
    istore_3 = 62,
    iadd = 96,
    _return = 177,
    getstatic = 178,
    invokevirtual = 182,
    invokespecial = 183,
    invokestatic = 184,
};

pub const OpCode = union(OpCodeTag) {
    iconst_0: NoParams,
    bipush: packed struct { byte: u8 },
    iload_1: NoParams,
    iload_2: NoParams,
    iload_3: NoParams,
    aload_0: NoParams,
    istore_1: NoParams,
    istore_2: NoParams,
    istore_3: NoParams,
    iadd: NoParams,
    _return: NoParams,
    getstatic: packed struct { index: u16 },
    invokevirtual: packed struct { index: u16 },
    invokespecial: packed struct { index: u16 },
    invokestatic: packed struct { index: u16 },

    pub fn toString(self: OpCode, alloc: std.mem.Allocator) []const u8 {
        return switch (self) {
            .iconst_0 => "iconst_0",
            .bipush => (std.fmt.allocPrint(
                alloc,
                "bipush #{d}",
                .{self.bipush.byte},
            ) catch "bipush"),
            .iload_1 => "iload_1",
            .iload_2 => "iload_2",
            .iload_3 => "iload_3",
            .aload_0 => "aload_0",
            .istore_1 => "istore_1",
            .istore_2 => "istore_2",
            .istore_3 => "istore_3",
            .iadd => "iadd",
            ._return => "return",
            .getstatic => (std.fmt.allocPrint(
                alloc,
                "getstatic #{d}",
                .{self.getstatic.index},
            ) catch "getstatic"),
            .invokevirtual => (std.fmt.allocPrint(
                alloc,
                "invokevirtual #{d}",
                .{self.invokevirtual.index},
            ) catch "invokevirtual"),
            .invokespecial => (std.fmt.allocPrint(
                alloc,
                "invokespecial #{d}",
                .{self.invokespecial.index},
            ) catch "invokespecial"),
            .invokestatic => (std.fmt.allocPrint(
                alloc,
                "invokestatic #{d}",
                .{self.invokestatic.index},
            ) catch "invokestatic"),
        };
    }
};

pub fn parse_opcodes(bytes: []u8, alloc: std.mem.Allocator) ![]OpCode {
    var opcode_count: usize = 0;

    const size_map = getUnionSizeMap(OpCode);

    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        defer opcode_count += 1;
        const opcode = bytes[i];

        if (size_map[opcode]) |size| {
            i += size;
        } else {
            return std.debug.panic("Unknown opcode '{d}'\n", .{opcode});
        }
    }

    var fbs = std.io.fixedBufferStream(bytes);
    var reader = fbs.reader();
    const opcodes = try alloc.alloc(OpCode, opcode_count);

    for (opcodes) |*opcode| {
        const tag: OpCodeTag = @enumFromInt(try reader.readByte());
        opcode.* = switch (tag) {
            .iconst_0 => try readOp(.iconst_0, reader.any()),
            .bipush => try readOp(.bipush, reader.any()),
            .iload_1 => try readOp(.iload_1, reader.any()),
            .iload_2 => try readOp(.iload_2, reader.any()),
            .iload_3 => try readOp(.iload_3, reader.any()),
            .aload_0 => try readOp(.aload_0, reader.any()),
            .istore_1 => try readOp(.istore_1, reader.any()),
            .istore_2 => try readOp(.istore_2, reader.any()),
            .istore_3 => try readOp(.istore_3, reader.any()),
            .iadd => try readOp(.iadd, reader.any()),
            ._return => try readOp(._return, reader.any()),
            .getstatic => try readOp(.getstatic, reader.any()),
            .invokevirtual => try readOp(.invokevirtual, reader.any()),
            .invokespecial => try readOp(.invokespecial, reader.any()),
            .invokestatic => try readOp(.invokestatic, reader.any()),
        };
    }

    return opcodes;
}

fn readOp(comptime member: std.meta.FieldEnum(OpCode), reader: std.io.AnyReader) anyerror!OpCode {
    const union_type = std.meta.FieldType(OpCode, member);
    return @unionInit(OpCode, @tagName(member), try reader.readStructEndian(union_type, .big));
}

pub inline fn getUnionSizeMap(comptime UnionType: type) [255]?usize {
    var map = [_]?usize{null} ** 255;

    const union_info = @typeInfo(UnionType).Union;

    inline for (union_info.fields) |field| {
        const tag = @intFromEnum(std.meta.stringToEnum(OpCodeTag, field.name).?);
        map[tag] = @sizeOf(field.type);
    }
    return map;
}
