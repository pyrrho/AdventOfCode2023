const std = @import("std");
const ArrayList = std.ArrayList;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("MEMORY LEAK");
    }

    const file = try std.fs.cwd().openFile("src/day9_input.txt", .{});
    var buf_reader = std.io.bufferedReader(file.reader());
    const in_stream = buf_reader.reader();

    var buf = ArrayList(u8).init(allocator);
    defer buf.deinit();

    var sequences = ArrayList(ArrayList(i32)).init(allocator);
    defer {
        for (sequences.items) |seq| seq.deinit();
        sequences.deinit();
    }

    while (true) {
        in_stream.readUntilDelimiterArrayList(&buf, '\n', 1024) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        var seq = ArrayList(i32).init(allocator);

        var tokens = std.mem.tokenize(u8, buf.items, " ");
        while (tokens.next()) |token| {
            try seq.append(try std.fmt.parseInt(i32, token, 10));
        }

        try sequences.append(seq);
    }

    for (sequences.items) |seq| {
        std.mem.reverse(i32, seq.items);

        var end = seq.items.len - 1;
        while (true) {
            var i: usize = 0;
            var constant_delta = true;
            while (i < end) : (i += 1) {
                seq.items[i] = seq.items[i + 1] - seq.items[i];
                if (seq.items[i] != seq.items[0]) constant_delta = false;
            }

            end -= 1;
            if (constant_delta) break;
        }

        while (end < seq.items.len - 1) : (end += 1) {
            seq.items[end + 1] += seq.items[end];
        }
    }

    var sum: i32 = 0;
    for (sequences.items) |seq| {
        sum += seq.items[seq.items.len - 1];
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("sum: {}\n", .{sum});
}
