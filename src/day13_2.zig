const std = @import("std");
const ArrayList = std.ArrayList;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("MEMORY LEAK");
    }

    const file = try std.fs.cwd().openFile("src/day13_input.txt", .{});
    var buf_reader = std.io.bufferedReader(file.reader());
    const in_stream = buf_reader.reader();

    var sections_builder = ArrayList([][]const u8).init(allocator);
    var lines_builder = ArrayList([]const u8).init(allocator);
    defer sections_builder.deinit();
    defer lines_builder.deinit();

    while (true) {
        var line = ArrayList(u8).init(allocator);
        in_stream.readUntilDelimiterArrayList(&line, '\n', 1024) catch |err| switch (err) {
            error.EndOfStream => {
                try sections_builder.append(try lines_builder.toOwnedSlice());
                line.deinit();
                break;
            },
            else => return err,
        };

        if (line.items.len == 0) {
            try sections_builder.append(try lines_builder.toOwnedSlice());
            continue;
        }

        try lines_builder.append(try line.toOwnedSlice());
    }

    const sections = try sections_builder.toOwnedSlice();
    defer {
        for (sections) |lines| {
            for (lines) |line| {
                allocator.free(line);
            }
            allocator.free(lines);
        }
        allocator.free(sections);
    }

    var horizonal_agg: u64 = 0;
    var vertical_agg: u64 = 0;

    section_scan: for (sections) |lines| {
        const section_width = lines[0].len;
        const section_height = lines.len;

        // Iterate across the first two rows, looking for a 2x2 window of
        // elements with vertical symetery.
        var i: usize = 1;
        var window: [2][2]u8 = .{ .{ undefined, lines[0][0] }, .{ undefined, lines[1][0] } };
        row_scan: while (i < section_width) : (i += 1) {
            var smudges: u8 = 0;

            window = .{ .{ window[0][1], lines[0][i] }, .{ window[1][1], lines[1][i] } };

            if (window[0][0] != window[0][1] or
                window[1][0] != window[1][1])
            {
                smudges += 1;
                if (smudges > 1) continue :row_scan;
            }

            // Reset smudges s.t. we don't count one smudge in the initial 2x2
            // window twice.
            smudges = 0;

            // Scan the column of lines[j][i-1], lines[j][i] for vertical
            // symetery.
            var j: usize = 0;
            while (j < section_height) : (j += 1) {
                var left = i - 1;
                var right = i;
                while (true) : ({
                    left -= 1;
                    right += 1;
                }) {
                    if (lines[j][left] != lines[j][right]) {
                        smudges += 1;
                        if (smudges > 1) continue :row_scan;
                    }

                    // NB. had to move the check to the bottom b/c usize fun.
                    if (left == 0 or right == lines[j].len - 1) {
                        break;
                    }
                }
            }

            // If we haven't found _a_ smudge, it's not the right line of symmetry.
            if (smudges == 0) continue :row_scan;

            // Found a match. We're done with the section.
            vertical_agg += i;
            continue :section_scan;
        }

        // Iterate down the first two columns, looking for a 2x2 window of
        // elements with horizontal symetery.
        i = 1;
        window = .{ undefined, .{ lines[0][0], lines[0][1] } };
        column_scan: while (i < section_height) : (i += 1) {
            var smudges: u8 = 0;

            window = .{ window[1], .{ lines[i][0], lines[i][1] } };

            if (window[0][0] != window[1][0] or
                window[0][1] != window[1][1])
            {
                smudges += 1;
                if (smudges > 1) continue :column_scan;
            }

            // Reset smudges s.t. we don't count one smudge in the initial 2x2
            // window twice.
            smudges = 0;

            // Scan the row of lines[i-1][j], lines[i][j] for horizontal
            // symetery.
            var j: usize = 0;
            while (j < section_width) : (j += 1) {
                var top: usize = i - 1;
                var bottom: usize = i;
                while (true) : ({
                    top -= 1;
                    bottom += 1;
                }) {
                    if (lines[top][j] != lines[bottom][j]) {
                        smudges += 1;
                        if (smudges > 1) continue :column_scan;
                    }

                    // NB. had to move the check to the bottom b/c usize fun.
                    if (top == 0 or bottom == section_height - 1) {
                        break;
                    }
                }
            }

            // If we haven't found _a_ smudge, it's not the right line of symmetry.
            if (smudges == 0) continue :column_scan;

            // Found a match. We're done with the section.
            horizonal_agg += i;
            continue :section_scan;
        }
    }

    const summary = vertical_agg + (100 * horizonal_agg);
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Summary: {}\n", .{summary});
}
