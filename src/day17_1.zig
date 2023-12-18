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

    const path = try AStar(start, goal, grid, allocator);
    defer allocator.free(path);

    // Print that path
    // -------------------------------------------------------------------------
    var path_map = AutoHashMap(Node, ?Direction).init(allocator);
    var heat_loss: u64 = 0;
    defer path_map.deinit();
    for (path) |n| {
        try path_map.put(n[0], n[1]);
        heat_loss += grid.lines[n[0].y][n[0].x];
    }

    for (grid.lines, 0..) |row, y| {
        for (row, 0..) |_, x| {
            std.debug.print("{}", .{grid.lines[y][x]});
        }
        std.debug.print("    ", .{});
        for (row, 0..) |_, x| {
            if (path_map.get(Node{ .x = x, .y = y })) |dir| {
                const c: u8 = if (dir == null) '#' else switch (dir.?) {
                    .North => '^',
                    .South => 'v',
                    .West => '<',
                    .East => '>',
                };

                std.debug.print("{c}", .{c});
            } else {
                std.debug.print("{}", .{grid.lines[y][x]});
            }
        }
        std.debug.print("\n", .{});
    }

    std.debug.print("Heat loss: {}\n", .{heat_loss});
}

// Types
// =============================================================================

// Type Aliases
// ------------

const DirectionalNode = struct { node: Node, dir: Direction };
const ReversePath = struct { Node, Direction };

const ParentOf = AutoHashMap(TravelingNode, TravelingNode);

const ScoreMap = AutoHashMap(TravelingNode, u64);

// Structs
// -------

const Direction = enum(usize) {
    North,
    South,
    West,
    East,
};

const Node = struct {
    x: usize,
    y: usize,

    pub fn eql(self: Node, other: Node) bool {
        return self.x == other.x and self.y == other.y;
    }
};

const TravelingNode = struct {
    x: usize,
    y: usize,
    dir: Direction,
    steps: u8,

    pub fn eql(self: TravelingNode, other: TravelingNode) bool {
        return self.x == other.x and self.y == other.y and self.dir == other.dir and self.steps == other.steps;
    }
    pub fn atPositionOf(self: TravelingNode, other: Node) bool {
        return self.x == other.x and self.y == other.y;
    }
};

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

    // TODO: This might be where we limit the forward steps. If we can track
    //       previous steps, we can return std.math.MaxInt(u64) for the fourth
    //       consecutive forward step.
    pub fn weightOf(self: Grid, node: TravelingNode) u4 {
        return self.lines[node.y][node.x];
    }

    pub fn weightConsideringParents(
        self: Grid,
        next: Node,
        dir: Direction,
        current: Node,
        parents: ParentOf,
    ) u64 {
        var last = parents.get(current);
        var matching_steps: usize = 0;
        while (true) {
            if (last == null) break;
            if (last.?.dir != dir) break;

            matching_steps += 1;
            if (matching_steps == 3) break;

            last = parents.get(last.?.node);
        }

        return if (matching_steps == 3) U64_MAX else self.weightOf(next);
    }

    pub fn weightConsideringSteps(self: Grid, node: TravelingNode) u64 {
        return if (node.steps >= 4) U64_MAX else self.weightOf(node);
    }

    pub fn neighborsOf(self: Grid, node: TravelingNode) [4]?TravelingNode {
        var ret: [4]?TravelingNode = .{null} ** 4;
        var i: usize = 0;
        if (node.dir != .South and node.y > 0) {
            const steps = if (node.dir == .North) node.steps + 1 else 1;
            ret[i] = .{
                .x = node.x,
                .y = node.y - 1,
                .dir = .North,
                .steps = steps,
            };
            i += 1;
        }
        if (node.dir != .West and node.x < self.width - 1) {
            const steps = if (node.dir == .East) node.steps + 1 else 1;
            ret[i] = .{
                .x = node.x + 1,
                .y = node.y,
                .dir = .East,
                .steps = steps,
            };
            i += 1;
        }
        if (node.dir != .North and node.y < self.height - 1) {
            const steps = if (node.dir == .South) node.steps + 1 else 1;
            ret[i] = .{
                .x = node.x,
                .y = node.y + 1,
                .dir = .South,
                .steps = steps,
            };
            i += 1;
        }
        if (node.dir != .East and node.x > 0) {
            const steps = if (node.dir == .West) node.steps + 1 else 1;
            ret[i] = .{
                .x = node.x - 1,
                .y = node.y,
                .dir = .West,
                .steps = steps,
            };
            i += 1;
        }
        return ret;
    }
};

/// A structure for storing and retreving Nodes that are candidates for the next
/// step in the A* search. Nodes should be stored and returned in order of
/// minimum f_score.
const Frontier = struct {
    // FIXME: This should be a min-heap -- or a linear scan that acts like a
    //        min-heap.
    items: ArrayList(TravelingNode),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Frontier {
        return Frontier{
            .items = ArrayList(TravelingNode).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Frontier) void {
        self.items.deinit();
    }

    pub fn append(self: *Frontier, traveling: TravelingNode) !void {
        try self.items.append(traveling);
    }

    pub fn insertNoClobber(self: *Frontier, traveling: TravelingNode) !void {
        var should_append = true;
        for (self.items.items) |n| {
            if (traveling.eql(n)) {
                should_append = false;
                break;
            }
        }
        if (should_append) {
            try self.append(traveling);
        }
    }

    /// Remove the Node with the lowest score (as provided by the `score_map`) from
    /// the Frontier and return it.
    pub fn popMinWithMap(self: *Frontier, score_map: ScoreMap) !?TravelingNode {
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

fn AStar(start: Node, goal: Node, grid: Grid, allocator: std.mem.Allocator) ![]ReversePath {
    // Nodes to be evaluated.
    var frontier = Frontier.init(allocator);
    defer frontier.deinit();

    // Map from a Node N to the Node immediately preceding it on the cheapest
    // path from `start` to N that is currently known.
    var came_from = ParentOf.init(allocator);
    defer came_from.deinit();

    // Map from a Node N to the cost of the cheapest path from `start` to N
    // that is currently known.
    // If no value is found for N, `std.math.MaxInt(u64)` should be assumed.
    var g_score = ScoreMap.init(allocator);
    defer g_score.deinit();

    // Map from a Node N to our guess of the cheapest path from `start`, through
    // N to `goal`. Specifically, `f_score[N] = g_score[N] + heuristic(N)`.
    // If no value is found for N, `std.math.MaxInt(u64)` should be assumed.
    var f_score = ScoreMap.init(allocator);
    defer f_score.deinit();

    // Seed with one step to the East and South of the start.
    const east = TravelingNode{ .x = start.x + 1, .y = start.y, .dir = .East, .steps = 1 };
    try frontier.append(east);
    try g_score.put(east, grid.weightOf(east));
    try f_score.put(east, strightLineHeuristic(east, goal));

    const south = TravelingNode{ .x = start.x, .y = start.y + 1, .dir = .South, .steps = 1 };
    try frontier.append(south);
    try g_score.put(south, grid.weightOf(south));
    try f_score.put(south, strightLineHeuristic(south, goal));

    while (try frontier.popMinWithMap(f_score)) |current| {
        if (current.atPositionOf(goal)) {
            var ret = ArrayList(ReversePath).init(allocator);
            try reconstructPathArrayLsit(current, came_from, &ret);
            const foo = try ret.toOwnedSlice();
            return foo;
        }

        const current_g = g_score.get(current).?;

        const neighbors = grid.neighborsOf(current);
        for (neighbors) |neighbor| {
            if (neighbor == null) break;

            const neighbor_g = g_score.get(neighbor.?);
            const new_neighbor_g = sumCappingAtMax(
                u64,
                current_g,
                grid.weightConsideringSteps(neighbor.?),
            );

            if (neighbor_g == null or new_neighbor_g < neighbor_g.?) {
                const new_f_score = sumCappingAtMax(
                    u64,
                    new_neighbor_g,
                    strightLineHeuristic(neighbor.?, goal),
                );
                try came_from.put(neighbor.?, current);
                try g_score.put(neighbor.?, new_neighbor_g);
                try f_score.put(neighbor.?, new_f_score);

                try frontier.insertNoClobber(neighbor.?);
            }
        }
    }

    return error.UnresolvablePath;
}

fn strightLineHeuristic(current: TravelingNode, goal: Node) u64 {
    return ((goal.x - current.x) + (goal.y - current.y)) * 1;
}

fn reconstructPathArrayLsit(
    current: TravelingNode,
    came_from: ParentOf,
    ret: *ArrayList(ReversePath),
) !void {
    var n: ?TravelingNode = current;
    while (n != null) {
        try ret.append(.{ .{ .x = n.?.x, .y = n.?.y }, n.?.dir });
        n = came_from.get(n.?);
    }
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
