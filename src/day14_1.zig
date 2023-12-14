const std = @import("std");
const ArrayList = std.ArrayList;

// const Fill = enum {
//     Empty,
//     SolidRock,
//     MobileRock,
// };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("MEMORY LEAK");
    }

    const file = try std.fs.cwd().openFile("src/day14_input.txt", .{});
    var buf_reader = std.io.bufferedReader(file.reader());
    const in_stream = buf_reader.reader();

    var buf = ArrayList(u8).init(allocator);
    defer buf.deinit();

    // NB. Assumes there are <= 100 columns in our input.
    // NB. Assumes tehre are <= 100 rows per column.
    // var columns: [100][100]Fill = .{.{Fill.Empty} ** 100} ** 100;
    var columns: [100][100]u8 = .{.{0} ** 100} ** 100;
    var next_open_row: [100]usize = .{0} ** 100;
    // var columns: [10][10]u8 = .{.{0} ** 10} ** 10;
    // var next_open_row: [10]usize = .{0} ** 10;

    var i: usize = 0;
    while (true) : (i += 1) {
        in_stream.readUntilDelimiterArrayList(&buf, '\n', 1024) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        for (buf.items, 0..) |c, j| {
            switch (c) {
                // '.' => columns[j][i] = Fill.Empty,
                '.' => columns[j][i] = '.',
                '#' => {
                    // columns[j][i] = Fill.SolidRock;
                    columns[j][i] = '#';
                    next_open_row[j] = i + 1;
                },
                'O' => {
                    // columns[j][next_open_row[i]] = Fill.MobileRock;
                    columns[j][i] = '.';
                    columns[j][next_open_row[j]] = '0';
                    next_open_row[j] += 1;
                },
                else => @panic("Invalid input"),
            }
        }
    }

    const spaces_per_column = i;
    var northern_load: u64 = 0;
    for (columns) |column| {
        std.debug.print("Column: {s}\n", .{column});
        for (column, 0..) |fill, s| {

            // switch (fill) {
            //     Fill.Empty => continue,
            //     Fill.SolidRock => continue,
            //     Fill.MobileRock => {
            //         northern_load += spaces_per_column - s;
            //     },
            // }
            switch (fill) {
                '.' => continue,
                '#' => continue,
                '0' => {
                    northern_load += spaces_per_column - s;
                },
                else => @panic("wat"),
            }
        }
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Northern load: {}\n", .{northern_load});
}
