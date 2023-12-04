const std = @import("std");

const numberTup = std.meta.Tuple(&.{ []const u8, u8 });
const numbers = [_]numberTup{
    .{ "one", '1' },
    .{ "two", '2' },
    .{ "three", '3' },
    .{ "four", '4' },
    .{ "five", '5' },
    .{ "six", '6' },
    .{ "seven", '7' },
    .{ "eight", '8' },
    .{ "nine", '9' },
};

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const file = try std.fs.cwd().openFile("src/day1_input.txt", .{});
    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var buf: [128]u8 = undefined;
    var sum: u32 = 0;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if (line.len == 0) {
            continue;
        }

        var first: ?u8 = null;
        var last: ?u8 = null;

        var i: usize = 0;
        lineLoop: while (i < line.len) {
            const c = line[i];

            // Look for decimal digits as per day1_1
            if (c >= '0' and c <= '9') {
                first = if (first != null) first else c;
                last = c;
                i += 1;
                continue :lineLoop;
            }

            // Scan the list of spelled out numbers, doing... things
            numbersLoop: for (numbers) |tup| {
                const number = tup[0];
                const digit = tup[1];

                if (c != number[0]) {
                    continue :numbersLoop;
                }
                if (number.len > line.len - i) {
                    continue :numbersLoop;
                }
                if (!std.mem.eql(u8, line[i .. i + number.len], number)) {
                    continue :numbersLoop;
                }

                first = if (first != null) first else digit;
                last = digit;
                // Increment by one fewer than the length of the number in case
                // the last character of this number is shared with the first of
                // another; e.g. twone, eighthree, sevenine, etc.
                i += number.len - 1;
                continue :lineLoop;
            }

            i += 1;
        }

        // TODO: Assumes every line has >= 1 digit in
        const first_digit: u32 = (first.? - '0') * 10;
        const last_digit: u32 = last.? - '0';

        sum += first_digit + last_digit;
    }

    try stdout.print("Sum: {d}\n", .{sum});
}
