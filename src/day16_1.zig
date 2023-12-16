const std = @import("std");
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

const SAMPLE = false;
const FILE_PATH = if (SAMPLE) "src/day16_sample_input.txt" else "src/day16_input.txt";

const Direction = enum {
    North,
    South,
    West,
    East,
};

const Walker = struct { x: usize, y: usize, direction: Direction };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("MEMORY LEAK");
    }

    const file = try std.fs.cwd().openFile(FILE_PATH, .{});
    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var lines: [][]const u8 = undefined;
    {
        var lines_builder = ArrayList([]const u8).init(allocator);
        var line = ArrayList(u8).init(allocator);
        const writer = line.writer();

        while (true) {
            in_stream.streamUntilDelimiter(writer, '\n', 1024) catch |err| switch (err) {
                error.EndOfStream => break,
                else => {
                    line.deinit();
                    lines_builder.deinit();
                    return err;
                },
            };
            try lines_builder.append(try line.toOwnedSlice());
        }

        lines = try lines_builder.toOwnedSlice();
    }
    defer {
        for (lines) |l| {
            allocator.free(l);
        }
        defer allocator.free(lines);
    }

    const grid_height = lines.len;
    const grid_width = lines[0].len;

    // Let's find out if we can allocate a multi-dimensional array of
    // runtime-known dimensions on the heap.
    const flat_grid = try allocator.alloc(bool, grid_width * grid_height);
    @memset(flat_grid, false);

    const energized_grid = try allocator.alloc([]bool, grid_height);
    for (0..grid_height) |y| {
        energized_grid[y] = flat_grid[y * grid_width .. (y + 1) * grid_width];
    }

    defer {
        allocator.free(energized_grid);
        allocator.free(flat_grid);
    }

    // Start walking.
    var walkers = ArrayList(Walker).init(allocator);
    defer walkers.deinit();
    try walkers.append(Walker{ .x = 0, .y = 0, .direction = .East });

    while (walkers.items.len > 0) {
        const walker = walkers.pop();
        const new_walkers = step(walker, lines, energized_grid);
        for (new_walkers) |new_walker| {
            if (new_walker) |nw| try walkers.append(nw);
        }
    }

    var energized_tiles: u64 = 0;
    for (flat_grid) |tile| {
        if (tile) energized_tiles += 1;
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Energized tiles: {}\n", .{energized_tiles});
}

fn step(walker: Walker, lines: [][]const u8, energized_grid: [][]bool) [2]?Walker {
    const tile = lines[walker.y][walker.x];
    // Lol needless use of defer.
    defer energized_grid[walker.y][walker.x] = true;
    return switch (tile) {
        '.' => .{ moveWalker(walker, walker.direction, lines), null },
        '\\' => switch (walker.direction) {
            .North => .{ moveWalker(walker, .West, lines), null },
            .South => .{ moveWalker(walker, .East, lines), null },
            .West => .{ moveWalker(walker, .North, lines), null },
            .East => .{ moveWalker(walker, .South, lines), null },
        },
        '/' => switch (walker.direction) {
            .North => .{ moveWalker(walker, .East, lines), null },
            .South => .{ moveWalker(walker, .West, lines), null },
            .West => .{ moveWalker(walker, .South, lines), null },
            .East => .{ moveWalker(walker, .North, lines), null },
        },
        '|' => if (energized_grid[walker.y][walker.x])
            .{ null, null }
        else switch (walker.direction) {
            .North => .{ moveWalker(walker, .North, lines), null },
            .South => .{ moveWalker(walker, .South, lines), null },
            .West => .{ moveWalker(walker, .North, lines), moveWalker(walker, .South, lines) },
            .East => .{ moveWalker(walker, .North, lines), moveWalker(walker, .South, lines) },
        },
        '-' => if (energized_grid[walker.y][walker.x])
            .{ null, null }
        else switch (walker.direction) {
            .North => .{ moveWalker(walker, .West, lines), moveWalker(walker, .East, lines) },
            .South => .{ moveWalker(walker, .West, lines), moveWalker(walker, .East, lines) },
            .West => .{ moveWalker(walker, .West, lines), null },
            .East => .{ moveWalker(walker, .East, lines), null },
        },
        else => @panic("invalid input"),
    };
}

fn moveWalker(walker: Walker, direction: Direction, lines: [][]const u8) ?Walker {
    const new_loc = switch (direction) {
        .North => {
            if (walker.y == 0) return null;
            return .{ .x = walker.x, .y = walker.y - 1, .direction = direction };
        },
        .South => {
            if (walker.y == lines.len - 1) return null;
            return .{ .x = walker.x, .y = walker.y + 1, .direction = direction };
        },
        .West => {
            if (walker.x == 0) return null;
            return .{ .x = walker.x - 1, .y = walker.y, .direction = direction };
        },
        .East => {
            if (walker.x == lines[walker.y].len - 1) return null;
            return .{ .x = walker.x + 1, .y = walker.y, .direction = direction };
        },
    };
    if (new_loc) |l| {
        return Walker{
            .x = l.x,
            .y = l.y,
            .direction = direction,
        };
    }
    return null;
}
