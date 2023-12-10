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
    const s: Location = findStartLocation(&map);

    var walkers = [_]PipeWalker{ undefined, undefined };
    {
        var p_i: usize = 0;

        for ([_]Move{ .north, .east, .south, .west }) |dir| {
            var pw = PipeWalker{
                .loc = s,
                .dir = dir,
            };
            pw.step() catch continue;
            pw.step() catch continue;

            walkers[p_i] = pw;
            p_i += 1;

            if (p_i == 2) break;
        }
    }

    var steps: u32 = 2;
    while (true) {
        try walkers[0].step();
        try walkers[1].step();
        steps += 1;

        if (walkers[0].loc.row == walkers[1].loc.row and
            walkers[0].loc.col == walkers[1].loc.col)
        {
            break;
        }
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Steps: {}\n", .{steps});
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
    map: *const Map,
    row: usize,
    col: usize,
};

const Move = enum {
    north,
    east,
    south,
    west,
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
