const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

const U64_MAX = std.math.maxInt(u64);

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

const Point = [2]usize;

const NodesMapKey = Point;
const NodesMapValue = [4]?struct { point: Point, steps: u64, is_end: bool };
const NodesMap = AutoHashMap(NodesMapKey, NodesMapValue);

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

    // Construct the Grid from the input file
    // ======================================
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

    // Find all of the nodes in the Grid
    // =================================
    // This is done with a relatively simple flood fill. A frontier is init'd
    // with the starting point, and then the following steps are repeated until
    // the frontier is empty:
    //   1. Pop a Point off of the frontier.
    //   2. Construct a Walker for every pathable neighbor of that Point.
    //   3. Step each Walker until it reaches a node, a dead end, or the End.
    //      3b. If the Walker did not end at a dead end, record the number of
    //          steps taken by the walker as an edge off the current Point.
    //      3c. If the Walker reached a node that has not yet been visited, add
    //          that node to the frontier.
    //   4. Add the current Point to the visited set.
    var nodes = NodesMap.init(allocator);
    defer nodes.deinit();

    var frontier = ArrayList(Point).init(allocator);
    var visited = AutoHashMap(Point, void).init(allocator);
    defer frontier.deinit();
    defer visited.deinit();

    try frontier.append(START);

    while (frontier.items.len > 0) {
        const p = frontier.pop();

        var edges: NodesMapValue = .{null} ** 4;
        var i: usize = 0;

        neighors: for (grid.pathableNeighbors(p).points) |neighbor| {
            if (neighbor == null) break;

            var w = Walker{
                .allocator = allocator,
                .point = neighbor.?,
                .grid = &grid,
                .steps = 1,
                .visited = AutoHashMap(Point, void).init(allocator),
            };
            try w.visited.put(p, void{});
            defer w.deinit();

            while (w.step()) |_| {} else |err| switch (err) {
                error.DeadEnd => continue :neighors,
                error.AtEnd => {
                    edges[i] = .{
                        .point = w.point,
                        .steps = w.steps,
                        .is_end = true,
                    };
                    i += 1;
                },
                error.AtNode => {
                    edges[i] = .{
                        .point = w.point,
                        .steps = w.steps,
                        .is_end = false,
                    };
                    i += 1;

                    if (!visited.contains(w.point)) {
                        try frontier.append(w.point);
                    }
                },
                else => return err,
            }
        }

        try nodes.put(p, edges);
        try visited.put(p, void{});
    }
    // Add the End as a node
    try nodes.put(END, .{null} ** 4);

    // Debug print
    // ===========
    if (false) {
        std.debug.print("Nodes:\n", .{});
        var itr = nodes.iterator();
        while (itr.next()) |entry| {
            const node = entry.key_ptr.*;
            const edges = entry.value_ptr.*;
            std.debug.print("  ({d}, {d}) =>\n", .{ node[0], node[1] });
            for (edges) |edge| {
                if (edge == null) break;
                std.debug.print("                ({d}, {d}) {d}", .{ edge.?.point[0], edge.?.point[1], edge.?.steps });
                if (edge.?.is_end) std.debug.print(" END!", .{});
                std.debug.print("\n", .{});
            }
            std.debug.print("\n", .{});
        }
    }

    // Recursive walk all possible paths
    // =================================
    var node_idx_map = AutoHashMap(Point, usize).init(allocator);
    defer node_idx_map.deinit();
    {
        var itr = nodes.keyIterator();
        var i: usize = 0;
        while (itr.next()) |p| : (i += 1) try node_idx_map.put(p.*, i);
    }

    const number_of_nodes = nodes.count();
    const v = try allocator.alloc(bool, number_of_nodes);
    @memset(v, false);
    defer allocator.free(v);

    const max_steps = try recursiveWalk(allocator, START, v, 0, nodes, node_idx_map);

    // Well, that only takes about four minutes. Not bad.
    // ==================================================

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Max steps: {d}\n", .{max_steps});
}

fn recursiveWalk(
    allocator: Allocator,
    point: Point,
    visited: []bool,
    steps: u64,
    nodes: NodesMap,
    nodes_idxs: AutoHashMap(Point, usize),
) error{ OutOfMemory, DeadEnd }!u64 {
    if (point[0] == END[0] and point[1] == END[1]) return steps;

    const node_idx = nodes_idxs.get(point).?;
    visited[node_idx] = true;

    var steps_for_edge: [4]?u64 = .{null} ** 4;
    var i: usize = 0;

    const visited_c = try allocator.dupe(bool, visited);
    defer allocator.free(visited_c);

    const edges = nodes.get(point).?;
    for (edges) |edge| {
        if (edge == null) break;

        const next_point = edge.?.point;
        const next_idx = nodes_idxs.get(next_point).?;

        if (visited[next_idx]) continue;

        @memcpy(visited_c, visited);

        if (recursiveWalk(
            allocator,
            next_point,
            visited_c,
            steps + edge.?.steps,
            nodes,
            nodes_idxs,
        )) |s| {
            steps_for_edge[i] = s;
            i += 1;
        } else |err| switch (err) {
            error.DeadEnd => continue,
            else => return err,
        }
    }

    var max_steps: ?u64 = null;
    for (steps_for_edge) |s| {
        if (s == null) break;
        if (max_steps == null or s.? > max_steps.?) max_steps = s;
    }

    if (max_steps == null) return error.DeadEnd;

    return max_steps.?;
}

// fn memoizedWalk(point: Point, nodes: NodesMap, memo: *AutoHashMap(Point, u64)) !u64 {
//     if (memo.get(point)) |val| return val;

//     if (point[0] == END[0] and point[1] == END[1]) return 0;

// }

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
        const fill = self.getFill(point);
        std.debug.assert(fill != '#');

        const row = point[0];
        const col = point[1];

        const at_right = col == self.cols - 1;
        const at_bottom = row == self.rows - 1;
        const at_left = col == 0;
        const at_top = row == 0;

        const can_move_east = !at_right and self.getFill(.{ row, col + 1 }) != '#';
        const can_move_south = !at_bottom and self.getFill(.{ row + 1, col }) != '#';
        const can_move_west = !at_left and self.getFill(.{ row, col - 1 }) != '#';
        const can_move_north = !at_top and self.getFill(.{ row - 1, col }) != '#';

        var points: [4]?Point = .{null} ** 4;
        var i: usize = 0;

        if (can_move_east) {
            points[i] = .{ row, col + 1 };
            i += 1;
        }
        if (can_move_south) {
            points[i] = .{ row + 1, col };
            i += 1;
        }
        if (can_move_west) {
            points[i] = .{ row, col - 1 };
            i += 1;
        }
        if (can_move_north) {
            points[i] = .{ row - 1, col };
            i += 1;
        }

        return .{ .points = points, .count = i };
    }
};

const Walker = struct {
    allocator: Allocator,
    point: Point,
    grid: *const Grid,
    steps: u64 = 0,
    visited: AutoHashMap(Point, void),

    pub fn init(allocator: Allocator, grid: *const Grid) Walker {
        return .{
            .allocator = allocator,
            .point = START,
            .grid = grid,
            .visited = AutoHashMap(Point, void).init(allocator),
        };
    }

    pub fn deinit(self: *Walker) void {
        self.visited.deinit();
    }

    // FIXME: This should probably return some kind of tagged union rather than
    //        an error enum. Maybe DeadEnd is an error, but AtNode and AtEnd are
    //        expected results.
    pub fn step(self: *Walker) !void {
        if (self.point[0] == END[0] and self.point[1] == END[1]) {
            return error.AtEnd;
        }

        if (self.grid.isNode(self.point)) {
            return error.AtNode;
        }

        const neighbors = self.grid.getNeighbors(self.point);

        var next: ?Point = null;
        for ([_]Direction{ .east, .south, .west, .north }) |dir| {
            if (neighbors[@intFromEnum(dir)] == null) continue;
            const neighbor = neighbors[@intFromEnum(dir)].?;

            if (self.grid.getFill(neighbor) == '#') continue;
            if (self.visited.contains(neighbor)) continue;

            std.debug.assert(next == null);
            next = neighbor;
        }

        if (next == null) {
            return error.DeadEnd;
        }

        self.steps += 1;
        try self.visited.put(self.point, void{});
        self.point = next.?;
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
};
