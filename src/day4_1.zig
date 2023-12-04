const std = @import("std");
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("MEMORY LEAK");
    }

    const file = try std.fs.cwd().openFile("src/day4_input.txt", .{});
    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var buf = ArrayList(u8).init(allocator);
    defer buf.deinit();

    var sum: u64 = 0;

    while (true) {
        in_stream.readUntilDelimiterArrayList(&buf, '\n', 4096) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        if (buf.items.len == 0) {
            continue;
        }

        // Move past "Card ###: "
        // TODO: Assumes every line starts with exactly "Card +\d+: "
        const index_of_start = std.mem.indexOf(u8, buf.items, ":").? + 2;
        const line = buf.items[index_of_start..];

        var winners_and_number = std.mem.split(u8, line, " | ");
        var winner_tokens = std.mem.tokenizeSequence(u8, winners_and_number.next().?, " ");
        var drawn_tokens = std.mem.tokenizeSequence(u8, winners_and_number.next().?, " ");

        var winners = AutoHashMap(u8, bool).init(allocator);
        defer winners.deinit();

        while (winner_tokens.next()) |n| {
            try winners.put(try std.fmt.parseInt(u8, n, 10), true);
        }

        var score: u32 = 0;
        while (drawn_tokens.next()) |drawn| {
            const n = try std.fmt.parseInt(u8, drawn, 10);

            if (winners.contains(n)) {
                score = if (score == 0) 1 else score * 2;
            }
        }

        sum += score;
    }

    try stdout.print("Sum: {}\n", .{sum});
}
