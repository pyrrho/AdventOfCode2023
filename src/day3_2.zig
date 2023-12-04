const std = @import("std");
const ArrayList = std.ArrayList;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("MEMORY LEAK");
    }

    const file = try std.fs.cwd().openFile("src/day3_input.txt", .{});
    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var sum: u64 = 0;

    var buffers = [3]ArrayList(u8){
        ArrayList(u8).init(allocator),
        ArrayList(u8).init(allocator),
        ArrayList(u8).init(allocator),
    };
    defer for (buffers) |buffer| {
        buffer.deinit();
    };

    try in_stream.readUntilDelimiterArrayList(&buffers[1], '\n', 256);
    try in_stream.readUntilDelimiterArrayList(&buffers[2], '\n', 256);

    const line_len = buffers[1].items.len;

    // Populate 'prev_line' with '.'s as a placeholder.
    try buffers[0].appendNTimes('.', line_len);

    var prev = &buffers[0];
    var curr = &buffers[1];
    var next = &buffers[2];

    var should_break = false;
    while (true) {
        const prev_line = prev.items;
        const curr_line = curr.items;
        const next_line = next.items;

        // std.debug.print("prev: {s}\n", .{prev_line});
        // std.debug.print("curr: {s}\n", .{curr_line});
        // std.debug.print("next: {s}\n", .{next_line});

        var i: usize = 0;
        while (std.mem.indexOfPos(u8, curr_line, i, "*")) |idx| : (i = idx + 1) {
            // Build a winidow of slices from the three relevant lines.
            // NB. Apparently guarding is unnecessary; the input has zero cases
            //     of a '*' within two characters of the left or right edge of a
            //     line. We'll always be given a full window.
            const window = [_][]u8{
                prev_line[left(idx, 3)..right(idx, 4, line_len)],
                curr_line[left(idx, 3)..right(idx, 4, line_len)],
                next_line[left(idx, 3)..right(idx, 4, line_len)],
            };
            const gear_idx = idx - left(idx, 3);

            std.debug.print("  window:{s}\n", .{window[0]});
            std.debug.print("         {s} -- gear idx: {}\n", .{ window[1], gear_idx });
            std.debug.print("         {s}\n", .{window[2]});

            // TODO: Would be more efficient to reuse this array list, just dump
            //       the ranges per loop
            var numbers = ArrayList([]u8).init(allocator);
            defer numbers.deinit();

            for (window) |row| {
                var j: usize = 0;
                while (j < row.len) {
                    if (!isDigit(row[j])) {
                        j += 1;
                        continue;
                    }

                    var k = j + 1;
                    while (k < row.len and isDigit(row[k])) {
                        k += 1;
                    }

                    const l = left(j, 1);
                    const r = right(k, 0, row.len);
                    if (l <= gear_idx and gear_idx <= r) {
                        try numbers.append(row[j..k]);
                    }

                    j = k;
                }
            }
            for (numbers.items) |num| {
                std.debug.print("    num: {s}\n", .{num});
            }

            if (numbers.items.len == 2) {
                const a = try std.fmt.parseInt(u64, numbers.items[0], 10);
                const b = try std.fmt.parseInt(u64, numbers.items[1], 10);
                sum += a * b;
            }

            std.debug.print("\n", .{});
        }

        if (should_break) {
            break;
        }

        // Advance the lines.
        const tmp = prev;
        prev = curr;
        curr = next;
        next = tmp;

        // Read the next line.
        in_stream.readUntilDelimiterArrayList(next, '\n', 256) catch |err| {
            if (err == error.EndOfStream) {
                // Hit the end of the file. Fill the next line with '.'s as a
                // placeholder, and run through the neighbor-detection for the
                // last time.
                next.clearRetainingCapacity();
                try next.appendNTimes('.', line_len);
                should_break = true;
            } else {
                return err;
            }
        };
    }

    try stdout.print("Sum: {d}\n", .{sum});
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

// This list was pulled from day3_input.txt -- it's all chars that are not a digit or '.'.
fn isSymbol(c: u8) bool {
    // return switch (c) {
    //     '-', '@', '*', '/', '&', '#', '%', '+', '=', '$' => true,
    //     else => false,
    // };
    return switch (c) {
        '.', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => false,
        else => true,
    };
}

fn left(n: usize, step: usize) usize {
    return if (n < step) 0 else n - step;
}
fn right(n: usize, step: usize, max: usize) usize {
    return if (max - step < n) max else n + step;
}

test "left and right" {
    try std.testing.expect(left(0, 3) == 0);
    try std.testing.expect(left(1, 3) == 0);
    try std.testing.expect(left(3, 3) == 0);
    try std.testing.expect(left(4, 3) == 1);
    try std.testing.expect(left(9, 3) == 6);

    try std.testing.expect(right(0, 3, 9) == 3);
    try std.testing.expect(right(3, 3, 9) == 6);
    try std.testing.expect(right(6, 3, 9) == 9);
    try std.testing.expect(right(7, 3, 9) == 9);
    try std.testing.expect(right(9, 3, 9) == 9);
}
