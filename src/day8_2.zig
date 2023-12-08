const std = @import("std");
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const __builtin_ctz = std.zig.c_builtins.__builtin_ctz;

const Node = struct {
    name: []const u8,
    left: []const u8,
    right: []const u8,
};

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("MEMORY LEAK");
    }

    const file = try std.fs.cwd().openFile("src/day8_input.txt", .{});
    var buf_reader = std.io.bufferedReader(file.reader());
    const in_stream = buf_reader.reader();
    var buf = ArrayList(u8).init(allocator);
    defer buf.deinit();

    // Extract "[LR]+" directions
    try in_stream.readUntilDelimiterArrayList(&buf, '\n', 1024);
    const directions = try std.mem.Allocator.dupe(allocator, u8, buf.items);
    defer allocator.free(directions);

    // Skip a newline.
    try in_stream.readUntilDelimiterArrayList(&buf, '\n', 1024);

    // Extract node definitions.
    var node_map = StringHashMap(Node).init(allocator);
    var starting_nodes = ArrayList([]const u8).init(allocator);

    while (true) {
        // "\w{3} = \(\w{3}, \w{3})"
        in_stream.readUntilDelimiterArrayList(&buf, '\n', 1024) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        const name_slice = buf.items[0..3];
        const left_name_slice = buf.items[7..10];
        const right_name_slice = buf.items[12..15];
        const name = try std.mem.Allocator.dupe(allocator, u8, name_slice);
        const left_name = try std.mem.Allocator.dupe(allocator, u8, left_name_slice);
        const right_name = try std.mem.Allocator.dupe(allocator, u8, right_name_slice);

        try node_map.put(name, Node{
            .name = name,
            .left = left_name,
            .right = right_name,
        });

        if (name[2] == 'A') {
            try starting_nodes.append(name);
        }
    }

    defer {
        var node_map_itr = node_map.iterator();
        while (node_map_itr.next()) |it| {
            const node = it.value_ptr.*;
            allocator.free(node.name);
            allocator.free(node.left);
            allocator.free(node.right);
        }

        node_map.deinit();
        starting_nodes.deinit();
    }

    // Start walking
    var path_steps = try ArrayList(u64).initCapacity(allocator, starting_nodes.items.len);
    defer path_steps.deinit();

    for (starting_nodes.items) |node_name| {
        var node = node_map.get(node_name).?;
        var d_idx: usize = 0;
        var steps: u64 = 0;

        while (true) {
            if (node.name[2] == 'Z') {
                break;
            }
            node = switch (directions[d_idx]) {
                'L' => node_map.get(node.left).?,
                'R' => node_map.get(node.right).?,
                else => @panic("Invalid direction"),
            };

            d_idx = (d_idx + 1) % directions.len;
            steps += 1;
        }

        try path_steps.append(steps);
    }

    const lcm = binaryLCMSlice(u64, path_steps.items);
    try stdout.print("steps: {}\n", .{lcm});
}

pub fn binaryGCD(comptime T: type, a: T, b: T) T {
    std.debug.assert(@typeInfo(T) == .Int);

    if (a == 0) return b;
    if (b == 0) return a;
    if (a == b) return a;

    var _a = a;
    var _b = b;

    var az = @as(u5, @intCast(@ctz(_a)));
    const bz = @as(u5, @intCast(@ctz(_b)));
    const shift = @min(az, bz);

    _b >>= bz;

    while (true) {
        _a >>= az;
        const diff = @as(T, @intCast(if (_b >= _a) _b - _a else _a - _b));
        _b = @min(_a, _b);

        if (diff == 0) {
            break;
        }

        az = @as(u5, @intCast(@ctz((diff))));
        _a = diff;
    }

    return _b << shift;
}

pub fn binaryGCDSlice(comptime T: type, s: []T) T {
    std.debug.assert(@typeInfo(T) == .Int);

    if (s.len == 0) return 0;
    if (s.len == 1) return s[0];

    var gcd = binaryGCD(T, s[0], s[1]);
    for (s[2..]) |x| {
        gcd = binaryGCD(T, gcd, x);
    }

    return gcd;
}

pub fn binaryLCM(comptime T: type, a: T, b: T) T {
    std.debug.assert(@typeInfo(T) == .Int);

    if (a == 0 and b == 0) return 0;
    const _a = @abs(a);
    const _b = @abs(b);

    return _a * @divExact(_b, binaryGCD(T, _a, _b));
}

pub fn binaryLCMSlice(comptime T: type, s: []T) T {
    std.debug.assert(@typeInfo(T) == .Int);

    if (s.len == 0) return 0;
    if (s.len == 1) return s[0];

    var lcm = binaryLCM(T, s[0], s[1]);
    for (s[2..]) |x| {
        lcm = binaryLCM(T, lcm, x);
    }

    return lcm;
}
