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

    var sum: u32 = 0;

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
        while (i < curr_line.len) {
            if (!isDigit(curr_line[i])) {
                i += 1;
                continue;
            }

            // Found a digit; figure out how long the number is.
            var j: usize = i + 1;
            while (j < line_len and isDigit(curr_line[j])) {
                j += 1;
            }

            // std.debug.print("  number found; {s}\n", .{curr_line[i..j]});

            // Now we know the length of the number, so we can build a list of
            // neighboring elements to scan for "symbols".
            const neighbors = [_][]u8{
                prev_line[left(i)..right(j, line_len)],
                curr_line[left(i)..i],
                curr_line[j..right(j, line_len)],
                next_line[left(i)..right(j, line_len)],
            };

            // std.debug.print("  neighbors:", .{});
            // for (neighbors) |neighbor| {
            //     std.debug.print(" {s}", .{neighbor});
            // }

            var neighboring_symbol = false;
            neighborSearch: for (neighbors) |neighbor| {
                for (neighbor) |c| {
                    if (isSymbol(c)) {
                        neighboring_symbol = true;
                        break :neighborSearch;
                    }
                }
            }

            // std.debug.print("  hit: {}\n", .{neighboring_symbol});

            // This number has a "symbol" neighbor, so we need to parse and sum it.
            if (neighboring_symbol) {
                const n = try std.fmt.parseInt(u16, curr_line[i..j], 10);
                sum += n;
            }

            i += j - i;
            continue;
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

fn min(a: usize, b: usize) usize {
    return if (a <= b) a else b;
}
fn max(a: usize, b: usize) usize {
    return if (a >= b) a else b;
}

fn left(a: usize) usize {
    return if (a == 0) 0 else a - 1;
}
fn right(a: usize, len: usize) usize {
    return if (a == len) len else a + 1;
}
