const std = @import("std");
const ArrayList = std.ArrayList;

const Point = struct {
    x: usize,
    y: usize,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("MEMORY LEAK");
    }

    const file = try std.fs.cwd().openFile("src/day11_input.txt", .{});
    var buf_reader = std.io.bufferedReader(file.reader());
    const in_stream = buf_reader.reader();

    var buf = ArrayList(u8).init(allocator);
    defer buf.deinit();

    // Read the first line so we can get some information about the sky.
    try in_stream.readUntilDelimiterArrayList(&buf, '\n', 1024);

    // NB. We assume the sky is a square.
    const sky_size = buf.items.len;

    const row_has_galaxy_tracker: []u64 = try allocator.alloc(u64, sky_size);
    const col_has_galaxy_tracker: []u64 = try allocator.alloc(u64, sky_size);
    defer allocator.free(row_has_galaxy_tracker);
    defer allocator.free(col_has_galaxy_tracker);

    { // TODO: There has ot be a better way to init elements to 0...
        var i: usize = 0;
        while (i < sky_size) : (i += 1) {
            row_has_galaxy_tracker[i] = 1000000 - 1;
            col_has_galaxy_tracker[i] = 1000000 - 1;
        }
    }

    // Iterate through the sky and find all the galaxies, marking rows and columns with at least one
    // galaxy in.
    var galaxies = ArrayList(Point).init(allocator);
    defer galaxies.deinit();

    {
        var y: usize = 0;
        while (true) : (y += 1) {
            var pos: usize = 0;
            while (std.mem.indexOfPos(u8, buf.items, pos, "#")) |x| {
                row_has_galaxy_tracker[y] = 0;
                col_has_galaxy_tracker[x] = 0;
                try galaxies.append(.{ .x = x, .y = y });
                pos = x + 1;
            }
            in_stream.readUntilDelimiterArrayList(&buf, '\n', 1024) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
        }
    }

    {
        var sum: u64 = 0;
        var i: usize = 0;
        while (i < sky_size) : (i += 1) {
            sum += row_has_galaxy_tracker[i];
            row_has_galaxy_tracker[i] = sum;
        }
    }
    {
        var sum: u64 = 0;
        var i: usize = 0;
        while (i < sky_size) : (i += 1) {
            sum += col_has_galaxy_tracker[i];
            col_has_galaxy_tracker[i] = sum;
        }
    }

    {
        var i: usize = 0;
        while (i < galaxies.items.len) : (i += 1) {
            galaxies.items[i].x += col_has_galaxy_tracker[galaxies.items[i].x];
            galaxies.items[i].y += row_has_galaxy_tracker[galaxies.items[i].y];
        }
    }

    var sum_of_distances: u64 = 0;
    {
        var i: usize = 0;
        while (i < galaxies.items.len) : (i += 1) {
            var j: usize = i + 1;
            while (j < galaxies.items.len) : (j += 1) {
                const x_diff = absSub(galaxies.items[i].x, galaxies.items[j].x);
                const y_diff = absSub(galaxies.items[i].y, galaxies.items[j].y);
                sum_of_distances += x_diff + y_diff;
            }
        }
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Sum of distances: {}\n", .{sum_of_distances});
}

fn absSub(l: usize, r: usize) usize {
    return if (l >= r) l - r else r - l;
}
