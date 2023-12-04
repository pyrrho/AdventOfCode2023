const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const file = try std.fs.cwd().openFile("src/day2_input.txt", .{});
    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var sum: u32 = 0;

    var buf: [4098]u8 = undefined;
    var game: u32 = 0;
    lineLoop: while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |full_line| {
        if (full_line.len == 0) {
            continue;
        }

        game += 1;

        // Move past "Game ###: "
        // TODO: Assumes every line starts with exactly "Game \d+: "
        const index_of_start = std.mem.indexOf(u8, full_line, ": ").? + 2;
        const line = full_line[index_of_start..];

        var pulls = std.mem.split(u8, line, "; ");
        while (pulls.next()) |pull| {
            var blocks = std.mem.split(u8, pull, ", ");
            while (blocks.next()) |block| {
                var details = std.mem.split(u8, block, " ");
                const count = try std.fmt.parseInt(u16, details.next().?, 10);
                const color = details.next().?;

                if ((std.mem.eql(u8, color, "red") and count > 12) or
                    (std.mem.eql(u8, color, "green") and count > 13) or
                    (std.mem.eql(u8, color, "blue") and count > 14))
                {
                    continue :lineLoop;
                }
            }
        }

        sum += game;
    }

    try stdout.print("Sum: {d}\n", .{sum});
}
