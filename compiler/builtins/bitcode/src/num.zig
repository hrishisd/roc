const std = @import("std");
const always_inline = std.builtin.CallOptions.Modifier.always_inline;
const math = std.math;
const RocList = @import("list.zig").RocList;
const RocStr = @import("str.zig").RocStr;
const WithOverflow = @import("utils.zig").WithOverflow;
const roc_panic = @import("utils.zig").panic;

pub fn NumParseResult(comptime T: type) type {
    // on the roc side we sort by alignment; putting the errorcode last
    // always works out (no number with smaller alignment than 1)
    return extern struct {
        value: T,
        errorcode: u8, // 0 indicates success
    };
}

pub fn exportParseInt(comptime T: type, comptime name: []const u8) void {
    comptime var f = struct {
        fn func(buf: RocStr) callconv(.C) NumParseResult(T) {
            // a radix of 0 will make zig determine the radix from the frefix:
            //  * A prefix of "0b" implies radix=2,
            //  * A prefix of "0o" implies radix=8,
            //  * A prefix of "0x" implies radix=16,
            //  * Otherwise radix=10 is assumed.
            const radix = 0;
            if (std.fmt.parseInt(T, buf.asSlice(), radix)) |success| {
                return .{ .errorcode = 0, .value = success };
            } else |_| {
                return .{ .errorcode = 1, .value = 0 };
            }
        }
    }.func;
    @export(f, .{ .name = name ++ @typeName(T), .linkage = .Strong });
}

pub fn exportParseFloat(comptime T: type, comptime name: []const u8) void {
    comptime var f = struct {
        fn func(buf: RocStr) callconv(.C) NumParseResult(T) {
            if (std.fmt.parseFloat(T, buf.asSlice())) |success| {
                return .{ .errorcode = 0, .value = success };
            } else |_| {
                return .{ .errorcode = 1, .value = 0 };
            }
        }
    }.func;
    @export(f, .{ .name = name ++ @typeName(T), .linkage = .Strong });
}

pub fn exportPow(comptime T: type, comptime name: []const u8) void {
    comptime var f = struct {
        fn func(base: T, exp: T) callconv(.C) T {
            return std.math.pow(T, base, exp);
        }
    }.func;
    @export(f, .{ .name = name ++ @typeName(T), .linkage = .Strong });
}

pub fn exportIsFinite(comptime T: type, comptime name: []const u8) void {
    comptime var f = struct {
        fn func(input: T) callconv(.C) bool {
            return std.math.isFinite(input);
        }
    }.func;
    @export(f, .{ .name = name ++ @typeName(T), .linkage = .Strong });
}

pub fn exportAsin(comptime T: type, comptime name: []const u8) void {
    comptime var f = struct {
        fn func(input: T) callconv(.C) T {
            return std.math.asin(input);
        }
    }.func;
    @export(f, .{ .name = name ++ @typeName(T), .linkage = .Strong });
}

pub fn exportAcos(comptime T: type, comptime name: []const u8) void {
    comptime var f = struct {
        fn func(input: T) callconv(.C) T {
            return std.math.acos(input);
        }
    }.func;
    @export(f, .{ .name = name ++ @typeName(T), .linkage = .Strong });
}

pub fn exportAtan(comptime T: type, comptime name: []const u8) void {
    comptime var f = struct {
        fn func(input: T) callconv(.C) T {
            return std.math.atan(input);
        }
    }.func;
    @export(f, .{ .name = name ++ @typeName(T), .linkage = .Strong });
}

pub fn exportSin(comptime T: type, comptime name: []const u8) void {
    comptime var f = struct {
        fn func(input: T) callconv(.C) T {
            return @sin(input);
        }
    }.func;
    @export(f, .{ .name = name ++ @typeName(T), .linkage = .Strong });
}

pub fn exportCos(comptime T: type, comptime name: []const u8) void {
    comptime var f = struct {
        fn func(input: T) callconv(.C) T {
            return @cos(input);
        }
    }.func;
    @export(f, .{ .name = name ++ @typeName(T), .linkage = .Strong });
}

pub fn exportLog(comptime T: type, comptime name: []const u8) void {
    comptime var f = struct {
        fn func(input: T) callconv(.C) T {
            return @log(input);
        }
    }.func;
    @export(f, .{ .name = name ++ @typeName(T), .linkage = .Strong });
}

pub fn exportRoundF32(comptime T: type, comptime name: []const u8) void {
    comptime var f = struct {
        fn func(input: f32) callconv(.C) T {
            return @floatToInt(T, (@round(input)));
        }
    }.func;
    @export(f, .{ .name = name ++ @typeName(T), .linkage = .Strong });
}

pub fn exportRoundF64(comptime T: type, comptime name: []const u8) void {
    comptime var f = struct {
        fn func(input: f64) callconv(.C) T {
            return @floatToInt(T, (@round(input)));
        }
    }.func;
    @export(f, .{ .name = name ++ @typeName(T), .linkage = .Strong });
}

pub fn exportDivCeil(comptime T: type, comptime name: []const u8) void {
    comptime var f = struct {
        fn func(a: T, b: T) callconv(.C) T {
            return math.divCeil(T, a, b) catch @panic("TODO runtime exception for dividing by 0!");
        }
    }.func;
    @export(f, .{ .name = name ++ @typeName(T), .linkage = .Strong });
}

pub fn ToIntCheckedResult(comptime T: type) type {
    // On the Roc side we sort by alignment; putting the errorcode last
    // always works out (no number with smaller alignment than 1).
    return extern struct {
        value: T,
        out_of_bounds: bool,
    };
}

pub fn exportToIntCheckingMax(comptime From: type, comptime To: type, comptime name: []const u8) void {
    comptime var f = struct {
        fn func(input: From) callconv(.C) ToIntCheckedResult(To) {
            if (input > std.math.maxInt(To)) {
                return .{ .out_of_bounds = true, .value = 0 };
            }
            return .{ .out_of_bounds = false, .value = @intCast(To, input) };
        }
    }.func;
    @export(f, .{ .name = name ++ @typeName(From), .linkage = .Strong });
}

pub fn exportToIntCheckingMaxAndMin(comptime From: type, comptime To: type, comptime name: []const u8) void {
    comptime var f = struct {
        fn func(input: From) callconv(.C) ToIntCheckedResult(To) {
            if (input > std.math.maxInt(To) or input < std.math.minInt(To)) {
                return .{ .out_of_bounds = true, .value = 0 };
            }
            return .{ .out_of_bounds = false, .value = @intCast(To, input) };
        }
    }.func;
    @export(f, .{ .name = name ++ @typeName(From), .linkage = .Strong });
}

pub fn bytesToU16C(arg: RocList, position: usize) callconv(.C) u16 {
    return @call(.{ .modifier = always_inline }, bytesToU16, .{ arg, position });
}

fn bytesToU16(arg: RocList, position: usize) u16 {
    const bytes = @ptrCast([*]const u8, arg.bytes);
    return @bitCast(u16, [_]u8{ bytes[position], bytes[position + 1] });
}

pub fn bytesToU32C(arg: RocList, position: usize) callconv(.C) u32 {
    return @call(.{ .modifier = always_inline }, bytesToU32, .{ arg, position });
}

fn bytesToU32(arg: RocList, position: usize) u32 {
    const bytes = @ptrCast([*]const u8, arg.bytes);
    return @bitCast(u32, [_]u8{ bytes[position], bytes[position + 1], bytes[position + 2], bytes[position + 3] });
}

fn addWithOverflow(comptime T: type, self: T, other: T) WithOverflow(T) {
    switch (@typeInfo(T)) {
        .Int => {
            var answer: T = undefined;
            const overflowed = @addWithOverflow(T, self, other, &answer);
            return .{ .value = answer, .has_overflowed = overflowed };
        },
        else => {
            const answer = self + other;
            const overflowed = !std.math.isFinite(answer);
            return .{ .value = answer, .has_overflowed = overflowed };
        },
    }
}

pub fn exportAddWithOverflow(comptime T: type, comptime name: []const u8) void {
    comptime var f = struct {
        fn func(self: T, other: T) callconv(.C) WithOverflow(T) {
            return @call(.{ .modifier = always_inline }, addWithOverflow, .{ T, self, other });
        }
    }.func;
    @export(f, .{ .name = name ++ @typeName(T), .linkage = .Strong });
}

pub fn exportAddSaturatedInt(comptime T: type, comptime name: []const u8) void {
    comptime var f = struct {
        fn func(self: T, other: T) callconv(.C) T {
            const result = addWithOverflow(T, self, other);
            if (result.has_overflowed) {
                // We can unambiguously tell which way it wrapped, because we have N+1 bits including the overflow bit
                if (result.value < 0) {
                    return std.math.maxInt(T);
                } else {
                    return std.math.minInt(T);
                }
            } else {
                return result.value;
            }
        }
    }.func;
    @export(f, .{ .name = name ++ @typeName(T), .linkage = .Strong });
}

pub fn exportAddOrPanic(comptime T: type, comptime name: []const u8) void {
    comptime var f = struct {
        fn func(self: T, other: T) callconv(.C) T {
            const result = addWithOverflow(T, self, other);
            if (result.has_overflowed) {
                roc_panic("integer addition overflowed!", 1);
                unreachable;
            } else {
                return result.value;
            }
        }
    }.func;
    @export(f, .{ .name = name ++ @typeName(T), .linkage = .Strong });
}
