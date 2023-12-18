const std = @import("std");
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

const U64_MAX = std.math.maxInt(u64);

const SAMPLE = true;
const FILE_PATH = if (SAMPLE) "src/day17_sample_input.txt" else "src/day17_input.txt";
// The number and span of rows in the input files.
// FIXME: I'd like to remove this variable, and allow the whole program to be
//        executable without prior knowledge of the input file.
const Z = if (SAMPLE) 13 else 140;

// Entry Point
// =================================================================================

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

    // Read lines
    // -------------------------------------------------------------------------
    var grid: Grid = undefined;
    {
        var lines_builder = ArrayList([]u4).init(allocator);
        var line = ArrayList(u4).init(allocator);
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
                try line.append(@as(u4, @intCast(c - '0')));
            }
            buf.clearRetainingCapacity();

            try lines_builder.append(try line.toOwnedSlice());
        }

        grid = Grid.initFromLines(try lines_builder.toOwnedSlice(), allocator);
    }
    defer grid.deinit();

    // A*
    // -------------------------------------------------------------------------
    const start = Node{ .x = 0, .y = 0 };
    const goal = Node{ .x = grid.width - 1, .y = grid.height - 1 };

    const ret = try AStar(start, goal, grid, allocator);
    const path = ret.path;
    const heat_loss = ret.heat_loss;

    defer allocator.free(path);

    // Print that path
    // -------------------------------------------------------------------------
    if (SAMPLE) try grid.debugPrint(path, allocator);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Heat loss: {}\n", .{heat_loss});
}

// Types
// =============================================================================

const Direction = enum(usize) {
    North,
    South,
    West,
    East,
};

const Directionality = enum {
    NorthSouth,
    EastWest,
};

const Node = struct {
    x: usize,
    y: usize,

    pub fn eql(self: Node, other: Node) bool {
        return self.x == other.x and self.y == other.y;
    }
};

const NodeWithDirectionality = struct {
    node: Node,
    dir: Directionality,

    pub fn eql(self: NodeWithDirectionality, other: NodeWithDirectionality) bool {
        return self.node.eql(other.node) and self.dir == other.dir;
    }
};

const NodeWithDirection = struct {
    node: Node,
    dir: Direction,

    pub fn eql(self: NodeWithDirection, other: NodeWithDirection) bool {
        return self.node.eql(other.node) and self.dir == other.dir;
    }
};

const ParentOf = AutoHashMap(NodeWithDirectionality, NodeWithDirectionality);
const ScoreMap = AutoHashMap(NodeWithDirectionality, u64);

const Grid = struct {
    lines: [][]u4,
    width: usize,
    height: usize,
    allocator: std.mem.Allocator,

    pub fn initFromLines(lines: [][]u4, allocator: std.mem.Allocator) Grid {
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

    pub fn weightOf(self: Grid, node: Node) u4 {
        return self.lines[node.y][node.x];
    }

    pub fn weightBetween(self: Grid, current: Node, next: Node) u64 {
        std.debug.assert(current.x == next.x or current.y == next.y);

        var ret: u64 = 0;
        if (current.y == next.y) {
            const y = current.y;
            var x = current.x;
            while (x != next.x) {
                x = if (current.x < next.x) x + 1 else x - 1;
                ret += self.lines[y][x];
            }
        }
        if (current.x == next.x) {
            const x = current.x;
            var y = current.y;
            while (y != next.y) {
                y = if (current.y < next.y) y + 1 else y - 1;
                ret += self.lines[y][x];
            }
        }
        return ret;
    }

    pub fn neighborsOf(
        self: Grid,
        nwd: NodeWithDirectionality,
        comptime from: comptime_int,
        comptime to: comptime_int,
    ) [(to - from + 1) * 2]?NodeWithDirectionality {
        return switch (nwd.dir) {
            .NorthSouth => self.eastWestNeighborsOf(nwd.node, from, to),
            .EastWest => self.northSouthNeighborsOf(nwd.node, from, to),
        };
    }

    pub fn northSouthNeighborsOf(
        self: Grid,
        node: Node,
        comptime from: comptime_int,
        comptime to: comptime_int,
    ) [(to - from + 1) * 2]?NodeWithDirectionality {
        const len = (to - from + 1) * 2;
        var ret: [len]?NodeWithDirectionality = .{null} ** len;
        var i: usize = 0;

        for (from..(to + 1)) |j| {
            if (node.y < self.height - j) {
                ret[i] = .{ .node = .{ .x = node.x, .y = node.y + j }, .dir = .NorthSouth };
                i += 1;
            } else break;
        }
        for (from..(to + 1)) |j| {
            if (node.y >= j) {
                ret[i] = .{ .node = .{ .x = node.x, .y = node.y - j }, .dir = .NorthSouth };
                i += 1;
            } else break;
        }

        return ret;
    }

    pub fn eastWestNeighborsOf(
        self: Grid,
        node: Node,
        comptime from: comptime_int,
        comptime to: comptime_int,
    ) [(to - from + 1) * 2]?NodeWithDirectionality {
        const len = (to - from + 1) * 2;
        var ret: [len]?NodeWithDirectionality = .{null} ** len;
        var i: usize = 0;

        for (from..(to + 1)) |j| {
            if (node.x < self.width - j) {
                ret[i] = .{ .node = .{ .x = node.x + j, .y = node.y }, .dir = .EastWest };
                i += 1;
            } else break;
        }
        for (from..(to + 1)) |j| {
            if (node.x >= j) {
                ret[i] = .{ .node = .{ .x = node.x - j, .y = node.y }, .dir = .EastWest };
                i += 1;
            } else break;
        }

        return ret;
    }

    // pub fn neighborsOf(self: Grid, nwd: NodeWithDirectionality) [6]?NodeWithDirectionality {
    //     return switch (nwd.dir) {
    //         .NorthSouth => self.eastWestNeighborsOf(nwd.node),
    //         .EastWest => self.northSouthNeighborsOf(nwd.node),
    //     };
    // }

    // pub fn northSouthNeighborsOf(self: Grid, node: Node) [6]?NodeWithDirectionality {
    //     var ret: [6]?NodeWithDirectionality = .{null} ** 6;
    //     var i: usize = 0;

    //     for (5..11) |j| {
    //         if (node.y < self.height - j) {
    //             ret[i] = .{ .node = .{ .x = node.x, .y = node.y + j }, .dir = .NorthSouth };
    //             i += 1;
    //         } else break;
    //     }
    //     for (5..11) |j| {
    //         if (node.y >= j) {
    //             ret[i] = .{ .node = .{ .x = node.x, .y = node.y - j }, .dir = .NorthSouth };
    //             i += 1;
    //         } else break;
    //     }

    //     return ret;
    // }

    // pub fn eastWestNeighborsOf(self: Grid, node: Node) [6]?NodeWithDirectionality {
    //     var ret: [6]?NodeWithDirectionality = .{null} ** 6;
    //     var i: usize = 0;

    //     for (5..11) |j| {
    //         if (node.x < self.width - j) {
    //             ret[i] = .{ .node = .{ .x = node.x + j, .y = node.y }, .dir = .EastWest };
    //             i += 1;
    //         } else break;
    //     }
    //     for (5..11) |j| {
    //         if (node.x >= j) {
    //             ret[i] = .{ .node = .{ .x = node.x - j, .y = node.y }, .dir = .EastWest };
    //             i += 1;
    //         } else break;
    //     }

    //     return ret;
    // }

    pub fn debugPrint(self: Grid, path: []NodeWithDirection, allocator: std.mem.Allocator) !void {
        var path_map = AutoHashMap(Node, Direction).init(allocator);
        defer path_map.deinit();

        for (path) |n| {
            try path_map.put(n.node, n.dir);
        }

        for (self.lines, 0..) |row, y| {
            for (row, 0..) |_, x| {
                std.debug.print("{}", .{self.lines[y][x]});
            }
            std.debug.print("    ", .{});
            for (row, 0..) |_, x| {
                if (path_map.get(Node{ .x = x, .y = y })) |dir| {
                    const c: u8 = switch (dir) {
                        .North => '^',
                        .South => 'v',
                        .West => '<',
                        .East => '>',
                    };

                    std.debug.print("{c}", .{c});
                } else {
                    std.debug.print("{}", .{self.lines[y][x]});
                }
            }
            std.debug.print("\n", .{});
        }
    }
};

/// A structure for storing and retreving Nodes that are candidates for the next
/// step in the A* search. Nodes should be stored and returned in order of
/// minimum f_score.
const Frontier = struct {
    // FIXME: This should be a min-heap -- or a linear scan that acts like a
    //        min-heap.
    items: ArrayList(NodeWithDirectionality),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Frontier {
        return Frontier{
            .items = ArrayList(NodeWithDirectionality).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Frontier) void {
        self.items.deinit();
    }

    pub fn append(self: *Frontier, nwd: NodeWithDirectionality) !void {
        try self.items.append(nwd);
    }

    pub fn insertNoClobber(self: *Frontier, nwd: NodeWithDirectionality) !void {
        var should_append = true;
        for (self.items.items) |n| {
            if (nwd.eql(n)) {
                should_append = false;
                break;
            }
        }
        if (should_append) {
            try self.append(nwd);
        }
    }

    /// Remove the Node with the lowest score (as provided by the `score_map`) from
    /// the Frontier and return it.
    pub fn popMinWithMap(self: *Frontier, score_map: ScoreMap) ?NodeWithDirectionality {
        if (self.items.items.len == 0) return null;
        if (self.items.items.len == 1) return self.items.pop();

        var lowest_score: u64 = U64_MAX;
        var lowest_idx: usize = 0;
        for (self.items.items, 0..) |node, i| {
            if (score_map.get(node)) |score| {
                if (score < lowest_score) {
                    lowest_score = score;
                    lowest_idx = i;
                }
            }
        }
        return self.items.swapRemove(lowest_idx);
    }
};

// A* Search Algoritm
// =============================================================================

fn AStar(
    start: Node,
    goal: Node,
    grid: Grid,
    allocator: std.mem.Allocator,
) !struct { path: []NodeWithDirection, heat_loss: u64 } {
    // Nodes to be evaluated.
    var frontier = Frontier.init(allocator);
    defer frontier.deinit();

    // Map from a Node N to the Node immediately preceding it on the cheapest
    // path from `start` to N that is currently known.
    var parents = ParentOf.init(allocator);
    defer parents.deinit();

    // Map from a Node N to the cost of the cheapest path from `start` to N
    // that is currently known.
    // If no value is found for N, `std.math.MaxInt(u64)` should be assumed.
    var g_score_map = ScoreMap.init(allocator);
    defer g_score_map.deinit();

    // Map from a Node N to our guess of the cheapest path from `start`, through
    // N to `goal`. Specifically, `f_score[N] = g_score[N] + heuristic(N)`.
    // If no value is found for N, `std.math.MaxInt(u64)` should be assumed.
    var f_score_map = ScoreMap.init(allocator);
    defer f_score_map.deinit();

    const ns = NodeWithDirectionality{ .node = start, .dir = .NorthSouth };
    try frontier.append(ns);
    try g_score_map.put(ns, 0);
    try f_score_map.put(ns, strightLineHeuristic(start, goal));

    const ew = NodeWithDirectionality{ .node = start, .dir = .EastWest };
    try frontier.append(ew);
    try g_score_map.put(ew, 0);
    try f_score_map.put(ew, strightLineHeuristic(start, goal));

    // This isn't a typical A* implementation, because it needs to account for
    // the dynamic nature of previous steps affecting the outcome. However, once
    // a route from `start` to `goal` is found, we can stop considering any path
    // with a g_score greater than the g_score of that path.
    var maximum_g_score: u64 = U64_MAX;
    var shortest_path_termination: ?NodeWithDirectionality = null;

    // Process the frontier.
    while (frontier.popMinWithMap(f_score_map)) |current| {
        const current_g = g_score_map.get(current) orelse @panic("No g_score found for current node");

        if (current_g >= maximum_g_score) continue;

        if (goal.eql(current.node)) {
            maximum_g_score = @min(current_g, maximum_g_score);
            shortest_path_termination = current;

            if (SAMPLE) {
                const path = try constructPath(current, parents, allocator);
                defer allocator.free(path);

                try grid.debugPrint(path, allocator);
                std.debug.print("heat loss: {}\n\n", .{maximum_g_score});
            }
            continue;
        }

        const neighbors = grid.neighborsOf(current, 4, 10);
        for (neighbors) |_neighbor| {
            if (_neighbor == null) break;
            const neighbor = _neighbor.?;

            const neighbor_g = g_score_map.get(neighbor);
            const new_neighbor_g = current_g + grid.weightBetween(current.node, neighbor.node);

            if (neighbor_g == null or new_neighbor_g < neighbor_g.?) {
                const new_f_score = new_neighbor_g + strightLineHeuristic(neighbor.node, goal);
                try parents.put(neighbor, current);
                try g_score_map.put(neighbor, new_neighbor_g);
                try f_score_map.put(neighbor, new_f_score);

                try frontier.insertNoClobber(neighbor);
            }
        }
    }

    if (shortest_path_termination == null) return error.UnresolvablePath;

    // Reconstruct the path.
    return .{
        .path = try constructPath(shortest_path_termination.?, parents, allocator),
        .heat_loss = maximum_g_score,
    };
}

fn constructPath(
    start: NodeWithDirectionality,
    parents: ParentOf,
    allocator: std.mem.Allocator,
) ![]NodeWithDirection {
    var ret = ArrayList(NodeWithDirection).init(allocator);
    var current = start;
    var _parent = parents.get(current);

    while (_parent != null) {
        const parent = _parent.?;
        switch (current.dir) {
            .NorthSouth => {
                if (parent.node.y < current.node.y) {
                    // traveling south
                    for (0..current.node.y - parent.node.y) |i| {
                        try ret.append(.{ .node = .{ .y = current.node.y - i, .x = current.node.x }, .dir = .South });
                    }
                }
                if (parent.node.y > current.node.y) {
                    // traveling north
                    for (0..parent.node.y - current.node.y) |i| {
                        try ret.append(.{ .node = .{ .y = current.node.y + i, .x = current.node.x }, .dir = .North });
                    }
                }
            },
            .EastWest => {
                if (parent.node.x < current.node.x) {
                    // traveling east
                    for (0..current.node.x - parent.node.x) |i| {
                        try ret.append(.{ .node = .{ .y = current.node.y, .x = current.node.x - i }, .dir = .East });
                    }
                }
                if (parent.node.x > current.node.x) {
                    // traveling west
                    for (0..parent.node.x - current.node.x) |i| {
                        try ret.append(.{ .node = .{ .y = current.node.y, .x = current.node.x + i }, .dir = .West });
                    }
                }
            },
        }

        current = parent;
        _parent = parents.get(current);
    }

    return ret.toOwnedSlice();
}

fn strightLineHeuristic(current: Node, goal: Node) u64 {
    const d_x = goal.x - current.x;
    const d_y = goal.y - current.y;
    const d = @sqrt(@as(f32, @floatFromInt(d_x * d_x + d_y * d_y)));
    return @as(u64, @intFromFloat(d));
}

fn sumCappingAtMax(comptime T: type, a: T, b: T) T {
    const T_MAX = std.math.maxInt(T);

    const c = a +% b;
    return if (c < a or c < b) T_MAX else c;
}

test "sumCappingAtMax" {
    try std.testing.expect(sumCappingAtMax(u64, 0, 0) == 0);
    try std.testing.expect(sumCappingAtMax(u64, 0, 1) == 1);
    try std.testing.expect(sumCappingAtMax(u64, 1, 0) == 1);
    try std.testing.expect(sumCappingAtMax(u64, 1, 1) == 2);
    try std.testing.expect(sumCappingAtMax(u64, U64_MAX, 0) == U64_MAX);
    try std.testing.expect(sumCappingAtMax(u64, 0, U64_MAX) == U64_MAX);
    try std.testing.expect(sumCappingAtMax(u64, U64_MAX - 1, 1) == U64_MAX);
    try std.testing.expect(sumCappingAtMax(u64, 1, U64_MAX - 1) == U64_MAX);
    try std.testing.expect(sumCappingAtMax(u64, U64_MAX - 1, 2) == U64_MAX);
    try std.testing.expect(sumCappingAtMax(u64, 2, U64_MAX - 1) == U64_MAX);
    try std.testing.expect(sumCappingAtMax(u64, U64_MAX, U64_MAX) == U64_MAX);
}
