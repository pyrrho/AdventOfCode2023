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
    INPUT.SAMPLE_1 => 10,
    INPUT.PRIMARY => 26501365,
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

    var grid_c: Grid = undefined;
    {
        var lines_builder = ArrayList([]Tile).init(allocator);
        var line = ArrayList(Tile).init(allocator);
        var buf = ArrayList(u8).init(allocator);
        defer buf.deinit();
        const writer = buf.writer();

        while (true) {
            in_stream.streamUntilDelimiter(writer, '\n', null) catch |err| switch (err) {
                error.EndOfStream => break,
                else => {
                    lines_builder.deinit();
                    line.deinit();
                    buf.deinit();
                    return err;
                },
            };

            for (buf.items) |c| {
                switch (c) {
                    '.', 'S' => try line.append(Tile.empty),
                    '#' => try line.append(Tile.stone),
                    else => unreachable,
                }
            }
            buf.clearRetainingCapacity();

            try lines_builder.append(try line.toOwnedSlice());
        }

        grid_c = Grid.initFromLines(allocator, try lines_builder.toOwnedSlice());
    }

    var grid_e = try grid_c.clone();
    var grid_se = try grid_c.clone();
    var grid_s = try grid_c.clone();
    var grid_sw = try grid_c.clone();
    var grid_w = try grid_c.clone();
    var grid_nw = try grid_c.clone();
    var grid_n = try grid_c.clone();
    var grid_ne = try grid_c.clone();

    defer {
        for ([_]*Grid{
            &grid_c,
            &grid_e,
            &grid_se,
            &grid_s,
            &grid_sw,
            &grid_w,
            &grid_nw,
            &grid_n,
            &grid_ne,
        }) |grid| grid.deinit();
    }

    var frontier = ArrayList(Point).init(allocator);
    defer frontier.deinit();
    for ([_]std.meta.Tuple(&.{ *Grid, Point, u32 }){
        .{ &grid_c, Point{ .x = 65, .y = 65 }, 0 },
        .{ &grid_e, Point{ .x = 0, .y = 65 }, 66 },
        .{ &grid_se, Point{ .x = 0, .y = 0 }, 132 },
        .{ &grid_s, Point{ .x = 65, .y = 0 }, 66 },
        .{ &grid_sw, Point{ .x = 130, .y = 0 }, 132 },
        .{ &grid_w, Point{ .x = 130, .y = 65 }, 66 },
        .{ &grid_nw, Point{ .x = 130, .y = 130 }, 132 },
        .{ &grid_n, Point{ .x = 65, .y = 130 }, 66 },
        .{ &grid_ne, Point{ .x = 0, .y = 130 }, 132 },
    }) |t| {
        const grid = t[0];
        const starting_point = t[1];
        var steps = t[2];

        grid.set(starting_point, Tile{ .filled = steps });
        steps += 1;

        try frontier.append(starting_point);

        while (frontier.items.len > 0) : (steps += 1) {
            const pending = try frontier.toOwnedSlice();
            defer frontier.allocator.free(pending);

            for (pending) |point| {
                const neighbors = grid.unfilledNeighborsOf(point);
                for (neighbors) |neighbor| {
                    if (neighbor == null) {
                        continue;
                    }

                    try frontier.append(neighbor.?);
                    grid.set(neighbor.?, Tile{ .filled = steps });
                }
            }
        }
    }

    var reachable_tiles: u64 = 0;
    for (grid_c.lines) |line| {
        for (line) |tile| {
            if (tile != .filled) continue;
            if (tile.filled % 2 == 1) {
                reachable_tiles += 1;
            }
        }
    }

    for ([_]Grid{
        grid_e,
        grid_s,
        grid_w,
        grid_n,
    }) |grid| {
        for (grid.lines) |line| {
            for (line) |tile| {
                if (tile != .filled) continue;
                if (tile.filled % 2 == 1) {
                    reachable_tiles += @divFloor(STEPS - tile.filled, 262) + 2;
                } else {
                    reachable_tiles += @divFloor(STEPS - tile.filled - 131, 262) + 2;
                }
            }
        }
    }

    var l: u64 = 0;
    for ([_]Grid{
        grid_se,
        grid_sw,
        grid_nw,
        grid_ne,
    }) |grid| {
        for (grid.lines) |line| {
            l += 1;
            if (l % 10 == 0) std.debug.print("l: {}\n", .{l});

            for (line) |tile| {
                if (tile != .filled) continue;
                var s: u64 = tile.filled;
                var a: u64 = 1;
                var c: bool = tile.filled % 2 == 1;

                while (s < STEPS) {
                    if (c) reachable_tiles += a;
                    a += 1;
                    s += 131;
                    c = !c;
                }

                // // 1 @ 132
                // // 2 @ 263
                // // 3 @ 394
                // if (tile.filled % 2 == 1) {
                //     reachable_tiles += @divFloor(STEPS - tile.filled, 262) + 2;
                // } else {
                //     reachable_tiles += @divFloor(STEPS - tile.filled - 131, 262) + 2;
                // }
            }
        }
    }

    // grid_c.debugPrintStep(64);
    grid_ne.debugPrintStep(263 - 131);

    // var reachable: u64 = 0;
    // for (grid.lines) |line| {
    //     for (line) |tile| {
    //         switch (tile) {
    //             Tile.empty => {},
    //             Tile.stone => {},
    //             Tile.filled => |s| {
    //                 if (s % 2 == 0) {
    //                     reachable += 1;
    //                 }
    //             },
    //         }
    //     }
    // }

    // if (false) {
    //     for (grid_c.lines) |line| {
    //         for (line) |tile| {
    //             switch (tile) {
    //                 Tile.empty => std.debug.print(".", .{}),
    //                 Tile.stone => std.debug.print("#", .{}),
    //                 Tile.filled => |s| {
    //                     if (s % 2 == 0) {
    //                         std.debug.print("O", .{});
    //                     } else {
    //                         std.debug.print("o", .{});
    //                     }
    //                 },
    //             }
    //         }
    //         std.debug.print("\n", .{});
    //     }
    //     std.debug.print("\n", .{});
    // }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Reachable Tiles: {}\n", .{reachable_tiles});
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
    ) Self {
        return Self{
            .lines = lines,
            .width = lines[0].len,
            .height = lines.len,
            .allocator = allocator,
        };
    }

    pub fn clone(self: Self) !Self {
        var lines = try self.allocator.alloc([]Tile, self.height);
        var i: usize = 0;
        while (i < self.height) : (i += 1) {
            lines[i] = try self.allocator.dupe(Tile, self.lines[i]);
        }

        return Self{
            .lines = lines,
            .width = self.width,
            .height = self.height,
            .allocator = self.allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.lines) |l| {
            self.allocator.free(l);
        }
        self.allocator.free(self.lines);
    }

    pub fn get(self: *Self, point: Point) Tile {
        return self.lines[point.y][point.x];
    }

    pub fn set(self: *Self, point: Point, tile: Tile) void {
        self.lines[point.y][point.x] = tile;
    }

    pub fn unfilledNeighborsOf(self: *Grid, point: Point) [4]?Point {
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

    pub fn debugPrintStep(self: Self, step: usize) void {
        var reachable_nodes: u64 = 0;
        for (self.lines) |line| {
            for (line) |tile| {
                switch (tile) {
                    Tile.empty => std.debug.print(".", .{}),
                    Tile.stone => std.debug.print("#", .{}),
                    Tile.filled => |s| {
                        if (s == step) {
                            std.debug.print("O", .{});
                            reachable_nodes += 1;
                        } else {
                            std.debug.print(".", .{});
                        }
                    },
                }
            }
            std.debug.print("\n", .{});
        }
        std.debug.print("Reachable Nodes: {}\n", .{reachable_nodes});
        std.debug.print("\n", .{});
    }
};
