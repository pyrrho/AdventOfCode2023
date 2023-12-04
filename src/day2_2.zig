const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const file = try std.fs.cwd().openFile("src/day2_input.txt", .{});
    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var sum: u32 = 0;

    var buf: [4098]u8 = undefined;
    var game: u32 = 0;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |full_line| {
        if (full_line.len == 0) {
            continue;
        }

        game += 1;

        var min_red: u16 = 0;
        var min_green: u16 = 0;
        var min_blue: u16 = 0;

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
                if (std.mem.eql(u8, color, "red")) {
                    min_red = if (min_red >= count) min_red else count;
                }
                if (std.mem.eql(u8, color, "green")) {
                    min_green = if (min_green >= count) min_green else count;
                }
                if (std.mem.eql(u8, color, "blue")) {
                    min_blue = if (min_blue >= count) min_blue else count;
                }
            }
        }

        sum += (min_red * min_green * min_blue);
    }

    try stdout.print("Sum: {d}\n", .{sum});
}
