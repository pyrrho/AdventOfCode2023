const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

const TARGET = INPUT.PRIMARY;
const INPUT = enum {
    SAMPLE_1,
    PRIMARY,
};
const FILE_PATH = switch (TARGET) {
    INPUT.SAMPLE_1 => "src/day23_sample_input.txt",
    INPUT.PRIMARY => "src/day23_input.txt",
};
const DIMENSIONS = switch (TARGET) {
    INPUT.SAMPLE_1 => .{ 23, 23 },
    INPUT.PRIMARY => .{ 141, 141 },
};

const START = Point{ 0, 1 };
const END = Point{ DIMENSIONS[0] - 1, DIMENSIONS[1] - 2 };

const EXPECTED_RESULT = switch (TARGET) {
    INPUT.SAMPLE_1 => "94",
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

    var grid: Grid = undefined;
    {
        var buf = ArrayList(u8).init(allocator);
        const writer = buf.writer();

        var lines_builder = ArrayList([]const u8).init(allocator);

        var row: usize = 0;
        while (true) : (row += 1) {
            in_stream.streamUntilDelimiter(writer, '\n', null) catch |err| switch (err) {
                error.EndOfStream => break,
                else => {
                    lines_builder.deinit();
                    buf.deinit();
                    return err;
                },
            };

            try lines_builder.append(try buf.toOwnedSlice());
        }

        grid = Grid.initFromLines(allocator, try lines_builder.toOwnedSlice());
    }
    defer grid.deinit();

    var frontier = ArrayList(Walker).init(allocator);
    defer frontier.deinit();

    try frontier.append(Walker.init(allocator, &grid, START));

    var max_steps: u64 = 0;
    frontier: while (frontier.items.len > 0) {
        var w = frontier.pop();
        defer w.deinit();

        // std.debug.print("Starting a walk from ({d}, {d}), heading {s}\n", .{ w.point[0], w.point[1], @tagName(w.previous_step) });

        while (w.step()) |_| {} else |err| switch (err) {
            error.AtNode => {
                // std.debug.print("Found node at ({d}, {d}) after {d} steps\n", .{ w.point[0], w.point[1], w.steps });
                // w.debugPrint();
                // std.debug.print("\n\n", .{});

                for (try w.split()) |next| {
                    if (next == null) continue :frontier;
                    try frontier.append(next.?);
                }
            },
            error.DeadEnd => {
                // std.debug.print("Found dead end at ({d}, {d}) after {d} steps\n", .{ w.point[0], w.point[1], w.steps });
                // w.debugPrint();
                // std.debug.print("\n\n", .{});

                continue :frontier;
            },
            error.AtEnd => {
                // std.debug.print("Found end at ({d}, {d}) after {d} steps\n", .{ w.point[0], w.point[1], w.steps });
                // w.debugPrint();
                // std.debug.print("\n\n", .{});

                if (w.steps > max_steps) max_steps = w.steps;
                continue :frontier;
            },
            else => return err,
        }
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Max steps: {d}\n", .{max_steps});
}

const Grid = struct {
    const Self = @This();

    allocator: Allocator,
    lines: [][]const u8,
    rows: usize,
    cols: usize,

    pub fn initFromLines(allocator: Allocator, lines: [][]const u8) Grid {
        return .{
            .allocator = allocator,
            .lines = lines,
            .rows = lines.len,
            .cols = lines[0].len,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.lines) |line| {
            self.allocator.free(line);
        }
        self.allocator.free(self.lines);
    }

    pub fn getFill(self: Self, point: Point) u8 {
        return self.lines[point[0]][point[1]];
    }

    pub fn getNeighbors(self: Self, point: Point) [4]?Point {
        const row = point[0];
        const col = point[1];

        const at_top = row == 0;
        const at_bottom = row == self.rows - 1;
        const at_left = col == 0;
        const at_right = col == self.cols - 1;

        var points: [4]?Point = .{null} ** 4;

        points[@intFromEnum(Direction.east)] = if (!at_right) .{ row, col + 1 } else null;
        points[@intFromEnum(Direction.south)] = if (!at_bottom) .{ row + 1, col } else null;
        points[@intFromEnum(Direction.west)] = if (!at_left) .{ row, col - 1 } else null;
        points[@intFromEnum(Direction.north)] = if (!at_top) .{ row - 1, col } else null;

        return points;
    }

    pub fn isNode(self: Self, point: Point) bool {
        const neighbors = self.getNeighbors(point);
        var count: usize = 0;
        for (neighbors) |neighbor| {
            if (neighbor == null) continue;
            if (self.getFill(neighbor.?) != '#') count += 1;
            if (count > 2) return true;
        }
        return false;
    }

    pub fn pathableNeighbors(self: Self, point: Point) struct { points: [4]?Point, count: usize } {
        const row = point[0];
        const col = point[1];
        const neighbors = self.getNeighbors(point);

        const fill = self.getFill(point);
        const can_move_east = fill == '.' or fill == '>';
        const can_move_south = fill == '.' or fill == 'v';
        const can_move_west = fill == '.' or fill == '<';
        const can_move_north = fill == '.' or fill == '^';

        var points: [4]?Point = .{null} ** 4;
        var i: usize = 0;

        if (can_move_east and
            neighbors[@intFromEnum(Direction.east)] != null and
            self.getFill(neighbors[@intFromEnum(Direction.east)].?) != '#')
        {
            points[i] = .{ row, col + 1 };
            i += 1;
        }
        if (can_move_south and
            neighbors[@intFromEnum(Direction.south)] != null and
            self.getFill(neighbors[@intFromEnum(Direction.south)].?) != '#')
        {
            points[i] = .{ row + 1, col };
            i += 1;
        }
        if (can_move_west and
            neighbors[@intFromEnum(Direction.west)] != null and
            self.getFill(neighbors[@intFromEnum(Direction.west)].?) != '#')
        {
            points[i] = .{ row, col - 1 };
            i += 1;
        }
        if (can_move_north and
            neighbors[@intFromEnum(Direction.north)] != null and
            self.getFill(neighbors[@intFromEnum(Direction.north)].?) != '#')
        {
            points[i] = .{ row - 1, col };
            i += 1;
        }

        return .{ .points = points, .count = i };
    }
};

const Point = [2]usize;

const Walker = struct {
    allocator: Allocator,
    point: Point,
    grid: *const Grid,
    previous_step: Direction = Direction.south,
    steps: u64 = 0,
    visited: AutoHashMap(Point, void),

    pub fn init(allocator: Allocator, grid: *const Grid, point: Point) Walker {
        return .{
            .allocator = allocator,
            .point = point,
            .grid = grid,
            .visited = AutoHashMap(Point, void).init(allocator),
        };
    }

    pub fn deinit(self: *Walker) void {
        self.visited.deinit();
    }

    pub fn step(self: *Walker) !void {
        if (self.point[0] == END[0] and self.point[1] == END[1]) {
            return error.AtEnd;
        }

        if (self.grid.isNode(self.point)) {
            return error.AtNode;
        }

        const fill = self.grid.getFill(self.point);
        const neighbors = self.grid.getNeighbors(self.point);

        var next: ?Point = null;
        // FIXME: There is zero error checking for invalid movement off of slopes.
        //        I don't like that.
        switch (fill) {
            '>' => next = neighbors[@intFromEnum(Direction.east)].?,
            'v' => next = neighbors[@intFromEnum(Direction.south)].?,
            '<' => next = neighbors[@intFromEnum(Direction.west)].?,
            '^' => next = neighbors[@intFromEnum(Direction.north)].?,
            '.' => {
                for ([_]Direction{ .east, .south, .west, .north }) |dir| {
                    // if (dir == Direction.reverse(self.previous_step)) continue;
                    if (neighbors[@intFromEnum(dir)] == null) continue;

                    const neighbor = neighbors[@intFromEnum(dir)].?;

                    if (self.grid.getFill(neighbor) == '#') continue;
                    if (self.visited.contains(neighbor)) continue;

                    std.debug.assert(next == null);
                    next = neighbor;
                }
            },
            else => return error.InvalidInput,
        }

        if (next == null) {
            return error.DeadEnd;
        }

        self.steps += 1;
        try self.visited.put(self.point, void{});
        self.point = next.?;
    }

    pub fn split(self: *Walker) ![3]?Walker {
        std.debug.assert(self.point[0] != END[0] or self.point[1] != END[1]);
        std.debug.assert(self.grid.isNode(self.point));
        std.debug.assert(self.grid.getFill(self.point) == '.');

        try self.visited.put(self.point, void{});
        self.steps += 1;

        var ret: [3]?Walker = .{null} ** 3;
        var i: usize = 0;

        const neighbors = self.grid.getNeighbors(self.point);

        for ([_]Direction{ .east, .south, .west, .north }) |dir| {
            // if (dir == Direction.reverse(self.previous_step)) continue;
            if (neighbors[@intFromEnum(dir)] == null) continue;

            const neighbor = neighbors[@intFromEnum(dir)].?;
            const neighbor_fill = self.grid.getFill(neighbor);

            if (neighbor_fill == '#') continue;
            if (dir == Direction.east and neighbor_fill == '<') continue;
            if (dir == Direction.south and neighbor_fill == '^') continue;
            if (dir == Direction.west and neighbor_fill == '>') continue;
            if (dir == Direction.north and neighbor_fill == 'v') continue;

            if (self.visited.contains(neighbor)) continue;

            ret[i] = .{
                .allocator = self.allocator,
                .point = neighbor,
                .grid = self.grid,
                .previous_step = dir,
                .steps = self.steps,
                .visited = try self.visited.clone(),
            };
            i += 1;
        }

        return ret;
    }

    pub fn debugPrint(self: Walker) void {
        for (self.grid.lines, 0..) |line, row| {
            for (line, 0..) |c, col| {
                if (row == self.point[0] and col == self.point[1]) {
                    std.debug.print("@", .{});
                } else if (self.visited.contains(.{ row, col })) {
                    std.debug.print("O", .{});
                } else {
                    std.debug.print("{c}", .{c});
                }
            }
            std.debug.print("\n", .{});
        }
    }
};

const Direction = enum(usize) {
    east = 0,
    south = 1,
    west = 2,
    north = 3,

    pub fn reverse(self: Direction) Direction {
        return switch (self) {
            Direction.east => Direction.west,
            Direction.south => Direction.north,
            Direction.west => Direction.east,
            Direction.north => Direction.south,
        };
    }
};
