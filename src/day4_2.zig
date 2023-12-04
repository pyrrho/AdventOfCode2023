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

    // This is a bit of a cheat, but I know there are 192 original cards, so
    // we're going to allocate a buffer with 192 elements to track how many of
    // each card we end up with.
    var cards: [192]u64 = .{1} ** 192;
    var idx: usize = 0;

    while (true) : (idx += 1) {
        in_stream.readUntilDelimiterArrayList(&buf, '\n', 4096) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

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
                score += 1;
            }
        }

        var j: u8 = 1;
        while (j <= score) : (j += 1) {
            if (idx + j < cards.len) {
                cards[idx + j] += cards[idx];
            }
        }
    }

    var num_cards: u64 = 0;
    for (cards) |card| {
        num_cards += card;
    }
    try stdout.print("Sum: {}\n", .{num_cards});
}
