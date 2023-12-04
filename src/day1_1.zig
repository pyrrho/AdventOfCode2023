const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const file = try std.fs.cwd().openFile("src/day1_1_input.txt", .{});
    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var buf: [1024]u8 = undefined;
    var sum: u32 = 0;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if (line.len == 0) {
            continue;
        }

        var first: ?u8 = null;
        var last: ?u8 = null;
        for (line) |c| {
            if (c >= '0' and c <= '9') {
                first = if (first != null) first else c;
                last = c;
            }
        }

        // TODO: Assumes every line has >= 1 digit in
        const first_digit: u32 = (first.? - '0') * 10;
        const last_digit: u32 = last.? - '0';

        sum += first_digit + last_digit;
    }

    try stdout.print("Sum: {d}\n", .{sum});
}
