const std = @import("std");
const StringHashMap = std.StringHashMap;

const Node = struct {
    name: []const u8,
    left: []const u8,
    right: []const u8,
};

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const file = try std.fs.cwd().openFile("src/day8_input.txt", .{});
    var buf_reader = std.io.bufferedReader(file.reader());
    const in_stream = buf_reader.reader();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("MEMORY LEAK");
    }

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    // Extract "[LR]+" directions
    try in_stream.readUntilDelimiterArrayList(&buf, '\n', 1024);
    const directions = try std.mem.Allocator.dupe(allocator, u8, buf.items);
    defer allocator.free(directions);

    // Skip a newline.
    try in_stream.readUntilDelimiterArrayList(&buf, '\n', 1024);

    // Extract node definitions.
    var node_map = StringHashMap(Node).init(allocator);

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
    }

    // Start walking
    var node = node_map.get("AAA").?;
    var idx: usize = 0;
    var steps: u64 = 0;
    while (true) {
        if (std.mem.eql(u8, node.name, "ZZZ")) break;

        node = switch (directions[idx]) {
            'L' => node_map.get(node.left).?,
            'R' => node_map.get(node.right).?,
            else => @panic("Invalid direction"),
        };

        idx = (idx + 1) % directions.len;
        steps += 1;
    }

    try stdout.print("steps: {}\n", .{steps});
}
