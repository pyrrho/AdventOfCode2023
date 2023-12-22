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
const DIM = switch (TARGET) {
    INPUT.SAMPLE_1 => 11,
    INPUT.PRIMARY => 131,
};
const STEPS = 26501365;
// const STEPS = 131 + 65;
const POLARITY = STEPS % 2;

const STEPS_TO_FIRST_EDGE = @divExact(DIM - 1, 2);
const SFE = STEPS_TO_FIRST_EDGE;

const GRIDS_RADIUS = @divExact(STEPS - STEPS_TO_FIRST_EDGE, DIM);
const GRID_COUNTS = [2]comptime_int{
    (GRIDS_RADIUS + 1) * (GRIDS_RADIUS + 1),
    GRIDS_RADIUS * GRIDS_RADIUS,
};
const GRID_CORNERS_TO_CUT = GRIDS_RADIUS + 1;
const GRID_CORNERS_TO_ADD = GRIDS_RADIUS;

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

    var grid: Grid = undefined;
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

        grid = Grid.initFromLines(allocator, try lines_builder.toOwnedSlice());
    }

    var grid_se = try grid.clone();
    var grid_sw = try grid.clone();
    var grid_nw = try grid.clone();
    var grid_ne = try grid.clone();
    var grid_e = try grid.clone();
    var grid_s = try grid.clone();
    var grid_w = try grid.clone();
    var grid_n = try grid.clone();

    const grids_points_steps = [_]std.meta.Tuple(&.{ *Grid, Point, u32 }){
        .{ &grid, Point{ .x = SFE, .y = SFE }, 0 },

        .{ &grid_se, Point{ .x = 0, .y = 0 }, DIM + 1 },
        .{ &grid_sw, Point{ .x = DIM - 1, .y = 0 }, DIM + 1 },
        .{ &grid_nw, Point{ .x = DIM - 1, .y = DIM - 1 }, DIM + 1 },
        .{ &grid_ne, Point{ .x = 0, .y = DIM - 1 }, DIM + 1 },

        .{ &grid_e, Point{ .x = 0, .y = SFE }, SFE + 1 },
        .{ &grid_s, Point{ .x = SFE, .y = 0 }, SFE + 1 },
        .{ &grid_w, Point{ .x = DIM - 1, .y = SFE }, SFE + 1 },
        .{ &grid_n, Point{ .x = SFE, .y = DIM - 1 }, SFE + 1 },
    };
    // const grids_points_steps = [_]std.meta.Tuple(&.{ *Grid, Point, u32 }){
    //     .{ &grid, Point{ .x = SFE, .y = SFE }, 0 },
    //     .{ &grid_se, Point{ .x = 0, .y = 0 }, 0 },
    //     .{ &grid_sw, Point{ .x = DIM - 1, .y = 0 }, 0 },
    //     .{ &grid_nw, Point{ .x = DIM - 1, .y = DIM - 1 }, 0 },
    //     .{ &grid_ne, Point{ .x = 0, .y = DIM - 1 }, 0 },
    //     .{ &grid_e, Point{ .x = 0, .y = SFE }, 0 },
    //     .{ &grid_s, Point{ .x = SFE, .y = 0 }, 0 },
    //     .{ &grid_w, Point{ .x = DIM - 1, .y = SFE }, 0 },
    //     .{ &grid_n, Point{ .x = SFE, .y = DIM - 1 }, 0 },
    // };
    const gpss = grids_points_steps;

    defer {
        for (gpss) |gps| gps[0].deinit();
    }

    for (gpss) |gps| try gps[0].fillFrom(gps[1], gps[2]);

    std.debug.print("STEPS:               {}\n", .{STEPS});
    std.debug.print("STEPS_TO_FIRST_EDGE: {}\n", .{STEPS_TO_FIRST_EDGE});
    std.debug.print("GRIDS_RADIUS:        {}\n", .{GRIDS_RADIUS});
    std.debug.print("GRID_COUNTS 0:       {}\n", .{GRID_COUNTS[0]});
    std.debug.print("GRID_COUNTS 1:       {}\n", .{GRID_COUNTS[1]});
    std.debug.print("\n", .{});

    // const sfe_extents = PredicateSet(SFE);
    const cardinal_extents = PredicateSet(SFE + DIM);
    _ = cardinal_extents;
    const diagonal_extents_add = PredicateSet(SFE + DIM);
    const diagonal_extents_sub = PredicateSet(SFE + DIM + DIM);

    const full_grid = [2]u64{
        grid.countFilledTilesMatching(eqlPolarity),
        grid.countFilledTilesMatching(neqPolarity),
    };

    const corners_to_add = grid_se.countFilledTilesMatching(diagonal_extents_add.leqEqlPolarity) +
        grid_sw.countFilledTilesMatching(diagonal_extents_add.leqEqlPolarity) +
        grid_nw.countFilledTilesMatching(diagonal_extents_add.leqEqlPolarity) +
        grid_ne.countFilledTilesMatching(diagonal_extents_add.leqEqlPolarity);

    const corners_to_remove = grid_se.countFilledTilesMatching(diagonal_extents_sub.gtEqlPolarity) +
        grid_sw.countFilledTilesMatching(diagonal_extents_sub.gtEqlPolarity) +
        grid_nw.countFilledTilesMatching(diagonal_extents_sub.gtEqlPolarity) +
        grid_ne.countFilledTilesMatching(diagonal_extents_sub.gtEqlPolarity);

    const reachable_tiles = (GRID_COUNTS[0] * full_grid[0]) +
        (GRID_COUNTS[1] * full_grid[1]) -
        (corners_to_remove * GRID_CORNERS_TO_CUT) +
        (corners_to_add * GRID_CORNERS_TO_ADD);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Reachable Tiles: {}\n", .{reachable_tiles});

    // grid_se.debugPrintReachable(diagonal_extents_add.leqEqlPolarity);

    // std.debug.print("full_grid[0]: {}\n", .{full_grid[0]});
    // std.debug.print("full_grid[1]: {}\n", .{full_grid[1]});

    // std.debug.print("\n", .{});
    // std.debug.print("\n", .{});

    // const past_extent_e = [2]u64{
    //     grid_e.countFilledTilesMatching(cardinal_extents.gtEqlPolarity),
    //     grid_e.countFilledTilesMatching(cardinal_extents.gtNeqPolarity),
    // };
    // const past_extent_s = [2]u64{
    //     grid_s.countFilledTilesMatching(cardinal_extents.gtEqlPolarity),
    //     grid_s.countFilledTilesMatching(cardinal_extents.gtNeqPolarity),
    // };
    // const past_extent_w = [2]u64{
    //     grid_w.countFilledTilesMatching(cardinal_extents.gtEqlPolarity),
    //     grid_w.countFilledTilesMatching(cardinal_extents.gtNeqPolarity),
    // };
    // const past_extent_n = [2]u64{
    //     grid_n.countFilledTilesMatching(cardinal_extents.gtEqlPolarity),
    //     grid_n.countFilledTilesMatching(cardinal_extents.gtNeqPolarity),
    // };

    // const past_extent_se = [2]u64{
    //     grid_se.countFilledTilesMatching(diagonal_extents_sub.gtEqlPolarity),
    //     grid_se.countFilledTilesMatching(diagonal_extents_sub.gtNeqPolarity),
    // };
    // const past_extent_sw = [2]u64{
    //     grid_sw.countFilledTilesMatching(diagonal_extents_sub.gtEqlPolarity),
    //     grid_sw.countFilledTilesMatching(diagonal_extents_sub.gtNeqPolarity),
    // };
    // const past_extent_nw = [2]u64{
    //     grid_nw.countFilledTilesMatching(diagonal_extents_sub.gtEqlPolarity),
    //     grid_nw.countFilledTilesMatching(diagonal_extents_sub.gtNeqPolarity),
    // };
    // const past_extent_ne = [2]u64{
    //     grid_ne.countFilledTilesMatching(diagonal_extents_sub.gtEqlPolarity),
    //     grid_ne.countFilledTilesMatching(diagonal_extents_sub.gtNeqPolarity),
    // };

    // std.debug.print("past_extent_ne[0]: {}\n", .{past_extent_ne[0]});
    // std.debug.print("past_extent_se[0]: {}\n", .{past_extent_se[0]});
    // std.debug.print("              sum: {}\n", .{past_extent_ne[0] + past_extent_se[0]});
    // std.debug.print("past_extent_e[0]:  {}\n", .{past_extent_e[0]});

    // std.debug.print("past_extent_ne[1]: {}\n", .{past_extent_ne[1]});
    // std.debug.print("past_extent_se[1]: {}\n", .{past_extent_se[1]});
    // std.debug.print("              sum: {}\n", .{past_extent_ne[1] + past_extent_se[1]});
    // std.debug.print("past_extent_e[1]:  {}\n", .{past_extent_e[1]});

    // std.debug.print("\n", .{});

    // std.debug.print("past_extent_se[0]: {}\n", .{past_extent_se[0]});
    // std.debug.print("past_extent_sw[0]: {}\n", .{past_extent_sw[0]});
    // std.debug.print("              sum: {}\n", .{past_extent_se[0] + past_extent_sw[0]});
    // std.debug.print("past_extent_s[0]:  {}\n", .{past_extent_s[0]});

    // std.debug.print("past_extent_se[1]: {}\n", .{past_extent_se[1]});
    // std.debug.print("past_extent_sw[1]: {}\n", .{past_extent_sw[1]});
    // std.debug.print("              sum: {}\n", .{past_extent_se[1] + past_extent_sw[1]});
    // std.debug.print("past_extent_s[1]:  {}\n", .{past_extent_s[1]});

    // std.debug.print("\n", .{});

    // std.debug.print("past_extent_nw[0]: {}\n", .{past_extent_nw[0]});
    // std.debug.print("past_extent_sw[0]: {}\n", .{past_extent_sw[0]});
    // std.debug.print("              sum: {}\n", .{past_extent_nw[0] + past_extent_sw[0]});
    // std.debug.print("past_extent_w[0]:  {}\n", .{past_extent_w[0]});

    // std.debug.print("past_extent_nw[1]: {}\n", .{past_extent_nw[1]});
    // std.debug.print("past_extent_sw[1]: {}\n", .{past_extent_sw[1]});
    // std.debug.print("              sum: {}\n", .{past_extent_nw[1] + past_extent_sw[1]});
    // std.debug.print("past_extent_w[1]:  {}\n", .{past_extent_w[1]});

    // std.debug.print("\n", .{});

    // std.debug.print("past_extent_ne[0]: {}\n", .{past_extent_ne[0]});
    // std.debug.print("past_extent_nw[0]: {}\n", .{past_extent_nw[0]});
    // std.debug.print("              sum: {}\n", .{past_extent_ne[0] + past_extent_nw[0]});
    // std.debug.print("past_extent_n[0]:  {}\n", .{past_extent_n[0]});

    // std.debug.print("past_extent_ne[1]: {}\n", .{past_extent_ne[1]});
    // std.debug.print("past_extent_nw[1]: {}\n", .{past_extent_nw[1]});
    // std.debug.print("              sum: {}\n", .{past_extent_ne[1] + past_extent_nw[1]});
    // std.debug.print("past_extent_n[1]:  {}\n", .{past_extent_n[1]});

    // std.debug.print("\n", .{});
    // std.debug.print("\n", .{});

    // // const within_extent_e = [2]u64{
    // //     grid_e.countFilledTilesMatching(cardinal_extents.leqEqlPolarity),
    // //     grid_e.countFilledTilesMatching(cardinal_extents.leqNeqPolarity),
    // // };
    // // const within_extent_s = [2]u64{
    // //     grid_s.countFilledTilesMatching(cardinal_extents.leqEqlPolarity),
    // //     grid_s.countFilledTilesMatching(cardinal_extents.leqNeqPolarity),
    // // };
    // // const within_extent_w = [2]u64{
    // //     grid_w.countFilledTilesMatching(cardinal_extents.leqEqlPolarity),
    // //     grid_w.countFilledTilesMatching(cardinal_extents.leqNeqPolarity),
    // // };
    // // const within_extent_n = [2]u64{
    // //     grid_n.countFilledTilesMatching(cardinal_extents.leqEqlPolarity),
    // //     grid_n.countFilledTilesMatching(cardinal_extents.leqNeqPolarity),
    // // };

    // const past_sfe_extent = [2]u64{
    //     grid.countFilledTilesMatching(sfe_extents.gtNeqPolarity),
    //     grid.countFilledTilesMatching(sfe_extents.gtEqlPolarity),
    // };

    // const within_extent_se = [2]u64{
    //     grid_se.countFilledTilesMatching(diagonal_extents_add.leqEqlPolarity),
    //     grid_se.countFilledTilesMatching(diagonal_extents_add.leqNeqPolarity),
    // };
    // const within_extent_sw = [2]u64{
    //     grid_sw.countFilledTilesMatching(diagonal_extents_add.leqEqlPolarity),
    //     grid_sw.countFilledTilesMatching(diagonal_extents_add.leqNeqPolarity),
    // };
    // const within_extent_nw = [2]u64{
    //     grid_nw.countFilledTilesMatching(diagonal_extents_add.leqEqlPolarity),
    //     grid_nw.countFilledTilesMatching(diagonal_extents_add.leqNeqPolarity),
    // };
    // const within_extent_ne = [2]u64{
    //     grid_ne.countFilledTilesMatching(diagonal_extents_add.leqEqlPolarity),
    //     grid_ne.countFilledTilesMatching(diagonal_extents_add.leqNeqPolarity),
    // };

    // std.debug.print("within_extent_se[0]: {}\n", .{within_extent_se[0]});
    // std.debug.print("within_extent_sw[0]: {}\n", .{within_extent_sw[0]});
    // std.debug.print("within_extent_nw[0]: {}\n", .{within_extent_nw[0]});
    // std.debug.print("within_extent_ne[0]: {}\n", .{within_extent_ne[0]});
    // std.debug.print("                sum: {}\n", .{within_extent_se[0] + within_extent_sw[0] + within_extent_nw[0] + within_extent_ne[0]});
    // std.debug.print("past_sfe_extent[0]:  {}\n", .{past_sfe_extent[0]});
    // std.debug.print("\n", .{});

    // std.debug.print("within_extent_se[1]: {}\n", .{within_extent_se[1]});
    // std.debug.print("within_extent_sw[1]: {}\n", .{within_extent_sw[1]});
    // std.debug.print("within_extent_nw[1]: {}\n", .{within_extent_nw[1]});
    // std.debug.print("within_extent_ne[1]: {}\n", .{within_extent_ne[1]});
    // std.debug.print("                sum: {}\n", .{within_extent_se[1] + within_extent_sw[1] + within_extent_nw[1] + within_extent_ne[1]});
    // std.debug.print("past_sfe_extent[1]:  {}\n", .{past_sfe_extent[1]});
    // std.debug.print("\n", .{});

    // std.debug.print("\n", .{});
    // std.debug.print("\n", .{});

    // grid_w.debugPrintReachable(cardinal_extents.leqEqlPolarity);
    // grid_sw.debugPrintReachable(diagonal_extents_add.leqEqlPolarity);

    // grid_sw.debugPrintReachable(diagonal_extents_sub.gtEqlPolarity);

    // grid.debugPrintReachable(p.eqlPolarity);
    // grid_s.debugPrintReachable(cardinal_extents.leqEqlPolarity);

    // grid.debugPrintReachable(SFE + DIM);
    // grid_s.debugPrintReachable(SFE + DIM);
    // grid_s.debugPrintReachable(SFE + DIM);
    // grid_sw.debugPrintReachable(SFE + DIM + DIM);
    // grid_sw.debugPrintStep(DIM + SFE - 1);
    // grid_sw.debugPrintStep(SFE + DIM + DIM);
    // grid_s.debugPrintStep(SFE + DIM + 1);

    // var even_grid_tiles: u64 = 0;
    // var odd_grid_tiles: u64 = 0;
    // var even_corners_tiles: u64 = 0;
    // var odd_corners_tiles: u64 = 0;
    // for (grid.lines) |line| {
    //     for (line) |tile| {
    //         if (tile != .filled) continue;
    //         if (tile.filled % 2 == 1) {
    //             odd_grid_tiles += 1;
    //             if (tile.filled >= 65) {
    //                 odd_corners_tiles += 1;
    //             }
    //         } else {
    //             even_grid_tiles += 1;
    //             if (tile.filled >= 65) {
    //                 even_corners_tiles += 1;
    //             }
    //         }
    //     }
    // }

    // for ([_]*Grid{
    //     &grid_se,
    //     &grid_sw,
    //     &grid_nw,
    //     &grid_ne,
    // }) |g| {
    //     for (g.lines) |line| {
    //         for (line) |tile| {
    //             if (tile != .filled) continue;
    //             if (tile.filled % 2 == 1) {
    //                 odd_corners_tiles += 1;
    //             } else {
    //                 even_corners_tiles += 1;
    //             }
    //         }
    //     }
    // }

    // const radius_grids_walked = @divExact(STEPS - 65, 131);
    // const number_odd_grids: u64 = (radius_grids_walked + 1) * (radius_grids_walked + 1);
    // const number_even_grids: u64 = radius_grids_walked * radius_grids_walked;
    // const number_odd_corners: u64 = (radius_grids_walked - 1);
    // const number_even_corners: u64 = radius_grids_walked;

    // const reachable_tiles = (number_odd_grids * odd_grid_tiles) +
    //     (number_even_grids * even_grid_tiles) -
    //     (number_odd_corners * odd_corners_tiles) +
    //     (number_even_corners * even_corners_tiles);
}

pub fn eqlPolarity(step: usize) bool {
    return step % 2 == POLARITY;
}

pub fn neqPolarity(step: usize) bool {
    return step % 2 != POLARITY;
}

fn PredicateSet(comptime I: comptime_int) type {
    return struct {
        pub fn gtEqlPolarity(step: usize) bool {
            return step % 2 == I % 2 and step > I;
        }
        pub fn gtNeqPolarity(step: usize) bool {
            return step % 2 != I % 2 and step > I;
        }

        pub fn geqEqlPolarity(step: usize) bool {
            return step % 2 == I % 2 and step >= I;
        }
        pub fn geqNeqPolarity(step: usize) bool {
            return step % 2 != I % 2 and step >= I;
        }

        pub fn ltEqlPolarity(step: usize) bool {
            return step % 2 == I % 2 and step < I;
        }
        pub fn ltNeqPolarity(step: usize) bool {
            return step % 2 != I % 2 and step < I;
        }

        pub fn leqEqlPolarity(step: usize) bool {
            return step % 2 == I % 2 and step <= I;
        }
        pub fn leqNeqPolarity(step: usize) bool {
            return step % 2 != I % 2 and step <= I;
        }
    };
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

    pub fn fillFrom(self: *Self, starting_point: Point, starting_step: usize) !void {
        self.set(starting_point, Tile{ .filled = starting_step });

        var frontier = ArrayList(Point).init(self.allocator);
        defer frontier.deinit();
        try frontier.append(starting_point);

        var steps = starting_step + 1;
        while (frontier.items.len > 0) : (steps += 1) {
            const pending = try frontier.toOwnedSlice();
            defer frontier.allocator.free(pending);

            for (pending) |point| {
                const neighbors = self.unfilledNeighborsOf(point);
                for (neighbors) |neighbor| {
                    if (neighbor == null) {
                        continue;
                    }

                    try frontier.append(neighbor.?);
                    self.set(neighbor.?, Tile{ .filled = steps });
                }
            }
        }
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

    pub fn countFilledTilesMatching(self: *Self, pred: *const fn (step: usize) bool) u64 {
        var ret: u64 = 0;
        for (self.lines) |line| {
            for (line) |tile| {
                if (tile != .filled) continue;
                if (pred(tile.filled)) {
                    ret += 1;
                }
            }
        }
        return ret;
    }

    pub fn debugPrintBounds(self: Self, step: usize) void {
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
    }

    pub fn debugPrintReachable(self: Self, pred: *const fn (step: usize) bool) void {
        var reachable_nodes: u64 = 0;
        for (self.lines) |line| {
            for (line) |tile| {
                switch (tile) {
                    Tile.empty => std.debug.print(".", .{}),
                    Tile.stone => std.debug.print("#", .{}),
                    Tile.filled => |s| {
                        if (pred(s)) {
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
    }
};
