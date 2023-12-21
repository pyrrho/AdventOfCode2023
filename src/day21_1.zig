const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const TARGET = INPUT.PRIMARY;
const INPUT = enum {
    SAMPLE_1,
    PRIMARY,
};
const FILE_PATH = switch (TARGET) {
    INPUT.SAMPLE_1 => "src/day21_sample_input.txt",
    INPUT.PRIMARY => "src/day21_input.txt",
};
const STEPS = switch (TARGET) {
    INPUT.SAMPLE_1 => 6,
    INPUT.PRIMARY => 64,
};
const EXPECTED_RESULT = switch (TARGET) {
    INPUT.SAMPLE_1 => "19",
    INPUT.PRIMARY => "???",
};

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

    var frontier = ArrayList(Point).init(allocator);
    defer frontier.deinit();

    var grid: Grid = undefined;
    {
        var lines_builder = ArrayList([]Tile).init(allocator);
        var line = ArrayList(Tile).init(allocator);
        var buf = ArrayList(u8).init(allocator);
        defer buf.deinit();
        const writer = buf.writer();

        var y: usize = 0;
        while (true) : (y += 1) {
            in_stream.streamUntilDelimiter(writer, '\n', null) catch |err| switch (err) {
                error.EndOfStream => break,
                else => {
                    lines_builder.deinit();
                    line.deinit();
                    buf.deinit();
                    return err;
                },
            };

            for (buf.items, 0..) |c, x| {
                switch (c) {
                    '.' => try line.append(Tile.empty),
                    '#' => try line.append(Tile.stone),
                    'S' => {
                        try line.append(Tile{ .filled = 0 });
                        try frontier.append(Point{ .x = x, .y = y });
                    },
                    else => unreachable,
                }
            }
            buf.clearRetainingCapacity();

            try lines_builder.append(try line.toOwnedSlice());
        }

        grid = Grid.initFromLines(allocator, try lines_builder.toOwnedSlice());
    }
    defer grid.deinit();

    for (1..STEPS + 1) |step| {
        const pending = try frontier.toOwnedSlice();
        defer frontier.allocator.free(pending);

        for (pending) |point| {
            const neighbors = grid.unfilledNeighborsOf(point);
            for (neighbors) |neighbor| {
                if (neighbor == null) {
                    continue;
                }

                try frontier.append(neighbor.?);
                grid.set(neighbor.?, Tile{ .filled = step });
            }
        }
    }

    var reachable: u64 = 0;
    for (grid.lines) |line| {
        for (line) |tile| {
            switch (tile) {
                Tile.empty => {},
                Tile.stone => {},
                Tile.filled => |s| {
                    if (s % 2 == 0) {
                        reachable += 1;
                    }
                },
            }
        }
    }

    if (false) {
        for (grid.lines) |line| {
            for (line) |tile| {
                switch (tile) {
                    Tile.empty => std.debug.print(".", .{}),
                    Tile.stone => std.debug.print("#", .{}),
                    Tile.filled => |s| {
                        if (s % 2 == 0) {
                            std.debug.print("O", .{});
                        } else {
                            std.debug.print("o", .{});
                        }
                    },
                }
            }
            std.debug.print("\n", .{});
        }
        std.debug.print("\n", .{});
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Reachable Tiles: {}\n", .{reachable});
}

// Types
// =============================================================================

const Tile = union(enum) {
    empty,
    stone,
    filled: usize,
};

const Point = struct {
    x: usize,
    y: usize,
};

const Direction = enum(usize) {
    East,
    South,
    West,
    North,
};

const Grid = struct {
    const Self = @This();

    lines: [][]Tile,
    width: usize,
    height: usize,

    allocator: Allocator,

    pub fn initFromLines(
        allocator: Allocator,
        lines: [][]Tile,
    ) Grid {
        return Grid{
            .lines = lines,
            .width = lines[0].len,
            .height = lines.len,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Grid) void {
        for (self.lines) |l| {
            self.allocator.free(l);
        }
        self.allocator.free(self.lines);
    }

    pub fn get(self: Self, point: Point) Tile {
        return self.lines[point.y][point.x];
    }

    pub fn set(self: *Self, point: Point, tile: Tile) void {
        self.lines[point.y][point.x] = tile;
    }

    pub fn unfilledNeighborsOf(self: Grid, point: Point) [4]?Point {
        var ret: [4]?Point = .{null} ** 4;

        if (point.x < self.width - 1) {
            if (self.get(Point{ .x = point.x + 1, .y = point.y }) == Tile.empty) {
                ret[@intFromEnum(Direction.East)] = Point{ .x = point.x + 1, .y = point.y };
            }
        }
        if (point.y < self.height - 1) {
            if (self.get(Point{ .x = point.x, .y = point.y + 1 }) == Tile.empty) {
                ret[@intFromEnum(Direction.South)] = Point{ .x = point.x, .y = point.y + 1 };
            }
        }
        if (point.x > 0) {
            if (self.get(Point{ .x = point.x - 1, .y = point.y }) == Tile.empty) {
                ret[@intFromEnum(Direction.West)] = Point{ .x = point.x - 1, .y = point.y };
            }
        }
        if (point.y > 0) {
            if (self.get(Point{ .x = point.x, .y = point.y - 1 }) == Tile.empty) {
                ret[@intFromEnum(Direction.North)] = Point{ .x = point.x, .y = point.y - 1 };
            }
        }

        return ret;
    }
};
