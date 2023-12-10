const std = @import("std");
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("MEMORY LEAK");
    }

    const file = try std.fs.cwd().openFile("src/day10_input.txt", .{});
    var buf_reader = std.io.bufferedReader(file.reader());
    const in_stream = buf_reader.reader();

    var lines = ArrayList(ArrayList(u8)).init(allocator);
    defer {
        for (lines.items) |line| {
            line.deinit();
        }
        lines.deinit();
    }

    // Build the map from the input file
    while (true) {
        var line = ArrayList(u8).init(allocator);
        in_stream.readUntilDelimiterArrayList(&line, '\n', 1024) catch |err| switch (err) {
            error.EndOfStream => {
                line.deinit();
                break;
            },
            else => return err,
        };

        try lines.append(line);
    }

    const map = Map.fromArrayList(lines);

    comptime if (false) {
        for (map.lines.items) |line| {
            std.debug.print("{s}\n", .{line.items});
        }
        std.debug.print("\n", .{});
        std.debug.print("\n", .{});
    };

    // Find the location of the 'S' on the map.
    const s: Location = findStartLocation(&map);

    // Start collecting all the locations of elements of the looped pipe.
    var pipe_locations = AutoHashMap(Location, void).init(allocator);
    defer pipe_locations.deinit();
    try pipe_locations.put(s, void{});

    // Detect the two valid moves from the starting location. Capture both,
    // - The PipeWalkers that move out from the starting location that will let
    //   us populate the pipe_locations map.
    // - The initial directions of the walkers that will let us identify the kind
    //   of pipe that sits at the starting location.
    var valid_moves = [_]Move{ undefined, undefined };
    var walkers = [_]PipeWalker{ undefined, undefined };
    {
        var i: usize = 0;

        for ([_]Move{ .north, .east, .south, .west }) |dir| {
            var pw = PipeWalker{
                .loc = s,
                .dir = dir,
            };
            pw.step() catch continue;
            try pipe_locations.put(pw.loc, void{});
            pw.step() catch {
                _ = pipe_locations.remove(pw.loc);
                continue;
            };
            try pipe_locations.put(pw.loc, void{});

            valid_moves[i] = dir;
            walkers[i] = pw;
            i += 1;

            if (i == 2) break;
        }
    }

    // Finish walking the PipeWalkers around the loop, populating the
    // pipe_locations map.
    while (true) {
        try walkers[0].step();
        try walkers[1].step();
        try pipe_locations.put(walkers[0].loc, void{});
        try pipe_locations.put(walkers[1].loc, void{});

        if (walkers[0].loc.row == walkers[1].loc.row and
            walkers[0].loc.col == walkers[1].loc.col)
        {
            break;
        }
    }

    comptime if (false) {
        std.debug.print("pipe elements:\n", .{});
        var ki = pipe_locations.keyIterator();
        while (ki.next()) |k| {
            std.debug.print("({d}, {d}) {c}\n", .{ k.row, k.col, k.element() });
        }
        std.debug.print("\n", .{});
        std.debug.print("\n", .{});
    };

    // Replate the 'S' in the map with the starting pipe.
    const starting_pipe: u8 = identifyStartingPipe(valid_moves);
    map.lines.items[s.row].items[s.col] = starting_pipe;

    comptime if (false) {
        for (map.lines.items) |line| {
            std.debug.print("{s}\n", .{line.items});
        }
        std.debug.print("\n", .{});
        std.debug.print("\n", .{});
    };

    // Build a directional flood search frontier, seeding the frontier/seen sets
    // with all edges of the map.

    var frontier = ArrayList(FloodStep).init(allocator);
    var seen = AutoHashMap(Location, void).init(allocator);
    defer frontier.deinit();
    defer seen.deinit();

    // // Diagonal motion isn't a thing, so add the four corners of the map to the
    // // seen set.
    // try seen.put(.{ .map = &map, .row = 0, .col = 0 }, void{});
    // try seen.put(.{ .map = &map, .row = 0, .col = map.col_len - 1 }, void{});
    // try seen.put(.{ .map = &map, .row = map.row_len - 1, .col = map.col_len - 1 }, void{});
    // try seen.put(.{ .map = &map, .row = map.row_len - 1, .col = 0 }, void{});

    // // Add the rest of each edge to both the frontier and seen sets.
    // for (1..map.col_len - 1) |i| {
    //     const l = .{ .map = &map, .row = 0, .col = i };
    //     try frontier.append(.{ .loc = l, .dir = .south });
    //     try seen.put(l, void{});
    // }
    // for (1..map.col_len - 1) |i| {
    //     const l = .{ .map = &map, .row = map.row_len - 1, .col = i };
    //     try frontier.append(.{ .loc = l, .dir = .north });
    //     try seen.put(l, void{});
    // }
    // for (1..map.row_len - 1) |i| {
    //     const l = .{ .map = &map, .row = i, .col = 0 };
    //     try frontier.append(.{ .loc = l, .dir = .east });
    //     try seen.put(l, void{});
    // }
    // for (1..map.row_len - 1) |i| {
    //     const l = .{ .map = &map, .row = i, .col = map.col_len - 1 };
    //     try frontier.append(.{ .loc = l, .dir = .west });
    //     try seen.put(l, void{});
    // }

    tryFlooding(&frontier, &seen, Location{ .map = &map, .row = 0, .col = 1 }, .south);

    while (frontier.popOrNull()) |flood_step| {
        // debugMap(&map, &seen, &pipe_locations, flood_step);

        // If we're not on an element of the pipe, flood in all directions.
        if (!pipe_locations.contains(flood_step.loc)) {
            for ([_]Move{ .north, .east, .south, .west }) |d| {
                tryFlooding(&frontier, &seen, flood_step.loc.move(d), d);
            }
            continue;
        }

        switch (flood_step.loc.element()) {
            '|' => switch (flood_step.dir) {
                .north => {
                    {
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.north), ._);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.east), ._);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.south), ._);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.west), ._);
                    }
                },
                .east => {
                    {
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.north), .east);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.east), ._);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.south), .east);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.west), .west);
                    }
                },
                .south => {
                    {
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.north), ._);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.east), ._);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.south), ._);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.west), ._);
                    }
                },
                .west => {
                    {
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.north), .west);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.east), .east);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.south), .west);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.west), ._);
                    }
                },
            },
            '-' => switch (flood_step.dir) {
                .north => {
                    {
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.north), ._);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.east), .north);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.south), .south);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.west), .north);
                    }
                },
                .east => {
                    {
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.north), ._);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.east), ._);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.south), ._);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.west), ._);
                    }
                },
                .south => {
                    {
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.north), .north);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.east), .south);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.south), ._);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.west), .south);
                    }
                },
                .west => {
                    {
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.north), ._);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.east), ._);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.south), ._);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.west), ._);
                    }
                },
            },
            'L' => switch (flood_step.dir) {
                .north => {
                    {
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.north), .east);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.east), .north);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.south), .south);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.west), .west);
                    }
                },
                .east => {
                    {
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.north), .east);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.east), .north);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.south), .south);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.west), .west);
                    }
                },
                .south => {
                    {
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.north), .west);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.east), .south);
                        // can't move south or west
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.south), ._);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.west), ._);
                    }
                },
                .west => {
                    {
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.north), .west);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.east), .south);
                        // can't move south or west
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.south), ._);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.west), ._);
                    }
                },
            },
            'J' => switch (flood_step.dir) {
                .north => {
                    {
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.north), .west);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.east), .east);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.south), .south);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.west), .north);
                    }
                },
                .east => {
                    {
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.north), .east);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.east), ._);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.south), ._);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.west), .south);
                    }
                },
                .south => {
                    {
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.north), .east);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.east), ._);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.south), ._);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.west), .south);
                    }
                },
                .west => {
                    {
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.north), .west);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.east), .east);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.south), .south);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.west), .north);
                    }
                },
            },
            '7' => switch (flood_step.dir) {
                .north => {
                    {
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.north), ._);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.east), ._);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.south), .east);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.west), .north);
                    }
                },
                .east => {
                    {
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.north), ._);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.east), ._);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.south), .east);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.west), .north);
                    }
                },
                .south => {
                    {
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.north), .north);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.east), .east);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.south), .west);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.west), .south);
                    }
                },
                .west => {
                    {
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.north), .north);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.east), .east);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.south), .west);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.west), .south);
                    }
                },
            },
            'F' => switch (flood_step.dir) {
                .north => {
                    {
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.north), ._);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.east), .north);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.south), .west);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.west), ._);
                    }
                },
                .east => {
                    {
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.north), .north);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.east), .south);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.south), .east);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.west), .west);
                    }
                },
                .south => {
                    {
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.north), .north);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.east), .south);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.south), .east);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.west), .west);
                    }
                },
                .west => {
                    {
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.north), ._);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.east), .north);
                        tryFlooding(&frontier, &seen, flood_step.loc.move(.south), .west);
                        // tryFlooding(&frontier, &seen, flood_step.loc.move(.west), ._);
                    }
                },
            },
            else => unreachable,
        }
    }

    const map_size = map.row_len * map.col_len;

    const stdout = std.io.getStdOut().writer();
    try stdout.print("enclosed elements: {}\n", .{map_size - seen.count()});
}

fn debugMap(
    map: *const Map,
    seen: *const AutoHashMap(Location, void),
    pipe_locations: *const AutoHashMap(Location, void),
    cur: FloodStep,
) void {
    var i: usize = 0;
    while (i < map.row_len) : (i += 1) {
        var j: usize = 0;
        while (j < map.col_len) : (j += 1) {
            if (cur.loc.row == i and cur.loc.col == j) {
                switch (cur.dir) {
                    .north => std.debug.print("{c}", .{'^'}),
                    .east => std.debug.print("{c}", .{'>'}),
                    .south => std.debug.print("{c}", .{'v'}),
                    .west => std.debug.print("{c}", .{'<'}),
                }
                continue;
            }
            const l = Location{ .map = map, .row = i, .col = j };
            if (seen.contains(l)) {
                std.debug.print("{c}", .{'*'});
            } else if (pipe_locations.contains(l)) {
                std.debug.print("{c}", .{l.element()});
            } else {
                std.debug.print("{c}", .{'.'});
            }
        }
        std.debug.print("\n", .{});
    }
    std.debug.print("\n", .{});
    std.debug.print("\n", .{});
}

fn findStartLocation(map: *const Map) Location {
    for (map.lines.items, 0..) |line, row| {
        if (std.mem.indexOf(u8, line.items, "S")) |col| {
            return Location{
                .map = map,
                .row = row,
                .col = col,
            };
        }
    }
    unreachable;
}

fn identifyStartingPipe(valid_moves: [2]Move) u8 {
    return switch (valid_moves[0]) {
        .north => switch (valid_moves[1]) {
            .north => unreachable,
            .east => 'L',
            .south => '|',
            .west => 'J',
        },
        .east => switch (valid_moves[1]) {
            .east => unreachable,
            .north => 'L',
            .south => 'F',
            .west => '-',
        },
        .south => switch (valid_moves[1]) {
            .south => unreachable,
            .north => '|',
            .east => 'F',
            .west => '7',
        },
        .west => switch (valid_moves[1]) {
            .west => unreachable,
            .north => 'J',
            .east => '-',
            .south => '7',
        },
    };
}

const FloodStep = struct { loc: Location, dir: Move };

fn tryFlooding(
    frontier: *ArrayList(FloodStep),
    seen: *AutoHashMap(Location, void),
    loc: TravelError!Location,
    dir: Move,
) void {
    if (loc) |l| {
        if (seen.contains(l)) return;
        frontier.append(.{ .loc = l, .dir = dir }) catch @panic("alloc error!");
        seen.put(l, void{}) catch @panic("alloc error!");
    } else |_| {}
}

const Map = struct {
    const Self = @This();

    lines: ArrayList(ArrayList(u8)),
    row_len: usize,
    col_len: usize,

    pub fn fromArrayList(lines: ArrayList(ArrayList(u8))) Map {
        const row_len = lines.items.len;
        const col_len = lines.items[0].items.len;
        return Map{
            .lines = lines,
            .row_len = row_len,
            .col_len = col_len,
        };
    }

    pub fn row(self: Self, idx: usize) MapRowAccessor {
        return MapRowAccessor{ .items = self.lines.items[idx].items };
    }
    const MapRowAccessor = struct {
        items: []const u8,

        pub fn col(self: MapRowAccessor, idx: usize) u8 {
            return self.items[idx];
        }
    };

    pub fn element(self: Self, loc: Location) u8 {
        return self.row(loc.row).col(loc.col);
    }

    pub fn deinit(self: Map) void {
        for (self.lines.items) |line| {
            line.deinit();
        }
        self.lines.deinit();
    }
};

const Location = struct {
    const Self = @This();

    map: *const Map,
    row: usize,
    col: usize,

    pub fn element(self: Self) u8 {
        return self.map.element(self);
    }

    pub fn move(self: Self, dir: Move) TravelError!Location {
        switch (dir) {
            .north => {
                if (self.row == 0) return TravelError.MapOverflow;
                return .{
                    .map = self.map,
                    .row = self.row - 1,
                    .col = self.col,
                };
            },
            .east => {
                if (self.col == self.map.col_len - 1) return TravelError.MapOverflow;
                return .{
                    .map = self.map,
                    .row = self.row,
                    .col = self.col + 1,
                };
            },
            .south => {
                if (self.row == self.map.row_len - 1) return TravelError.MapOverflow;
                return .{
                    .map = self.map,
                    .row = self.row + 1,
                    .col = self.col,
                };
            },
            .west => {
                if (self.col == 0) return TravelError.MapOverflow;
                return .{
                    .map = self.map,
                    .row = self.row,
                    .col = self.col - 1,
                };
            },
        }
    }
};

const Move = enum {
    north,
    east,
    south,
    west,

    pub fn opposite(self: Move) Move {
        return switch (self) {
            .north => .south,
            .east => .west,
            .south => .north,
            .west => .east,
        };
    }
};

const TravelError = error{
    InvalidDirection,
    MapOverflow,
    NonPathableLocation,
};

const PipeWalker = struct {
    const Self = @This();

    loc: Location,
    dir: Move,

    pub fn step(self: *Self) TravelError!void {
        switch (self.loc.map.element(self.loc)) {
            'S' => switch (self.dir) {
                .north => {
                    if (self.loc.row == 0) return TravelError.MapOverflow;
                    self.*.loc.row -= 1;
                    self.*.dir = .north;
                },
                .east => {
                    if (self.loc.col == self.loc.map.col_len - 1) return TravelError.MapOverflow;
                    self.*.loc.col += 1;
                    self.*.dir = .east;
                },
                .south => {
                    if (self.loc.row == self.loc.map.row_len - 1) return TravelError.MapOverflow;
                    self.*.loc.row += 1;
                    self.*.dir = .south;
                },
                .west => {
                    if (self.loc.col == 0) return TravelError.MapOverflow;
                    self.*.loc.col -= 1;
                    self.*.dir = .west;
                },
            },
            '|' => switch (self.dir) {
                .north => {
                    self.*.loc.row -= 1;
                    self.*.dir = .north;
                },
                .south => {
                    self.*.loc.row += 1;
                    self.*.dir = .south;
                },
                else => return TravelError.InvalidDirection,
            },
            '-' => switch (self.dir) {
                .east => {
                    self.*.loc.col += 1;
                    self.*.dir = .east;
                },
                .west => {
                    self.*.loc.col -= 1;
                    self.*.dir = .west;
                },
                else => return TravelError.InvalidDirection,
            },
            'L' => switch (self.dir) {
                .south => {
                    self.*.loc.col += 1;
                    self.*.dir = .east;
                },
                .west => {
                    self.*.loc.row -= 1;
                    self.*.dir = .north;
                },
                else => return TravelError.InvalidDirection,
            },
            'J' => switch (self.dir) {
                .south => {
                    self.*.loc.col -= 1;
                    self.*.dir = .west;
                },
                .east => {
                    self.*.loc.row -= 1;
                    self.*.dir = .north;
                },
                else => return TravelError.InvalidDirection,
            },
            '7' => switch (self.dir) {
                .north => {
                    self.*.loc.col -= 1;
                    self.*.dir = .west;
                },
                .east => {
                    self.*.loc.row += 1;
                    self.*.dir = .south;
                },
                else => return TravelError.InvalidDirection,
            },
            'F' => switch (self.dir) {
                .north => {
                    self.*.loc.col += 1;
                    self.*.dir = .east;
                },
                .west => {
                    self.*.loc.row += 1;
                    self.*.dir = .south;
                },
                else => return TravelError.InvalidDirection,
            },
            else => return TravelError.NonPathableLocation,
        }
    }
};
