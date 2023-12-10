const std = @import("std");
const ArrayList = std.ArrayList;

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
    const s: Location = findStartLocation(map);

    var locs = [_]Location{ undefined, undefined };
    var dirs = [_]Move{ undefined, undefined };
    {
        var p_i: usize = 0;

        for ([_]Move{ .north, .east, .south, .west }) |dir| {
            var l = Location{
                .row = s.row,
                .col = s.col,
            };
            _ = l.followPath(map, dir) catch continue;
            if (l.followPath(map, dir)) |new_dir| {
                locs[p_i] = l;
                dirs[p_i] = new_dir;
                p_i += 1;
            } else |_| {}

            if (p_i == 2) break;
        }
    }

    var steps: u32 = 2;
    while (true) {
        dirs[0] = try locs[0].followPath(map, dirs[0]);
        dirs[1] = try locs[1].followPath(map, dirs[1]);
        steps += 1;

        if (locs[0].row == locs[1].row and locs[0].col == locs[1].col) break;
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Steps: {}\n", .{steps});
}

const Move = enum {
    north,
    east,
    south,
    west,
};
const TravelError = error{
    BadPath,
};
const Location = struct {
    const Self = @This();

    row: usize,
    col: usize,

    pub fn followPath(self: *Self, map: Map, traveling: Move) TravelError!Move {
        switch (map.lines.items[self.row].items[self.col]) {
            'S' => switch (traveling) {
                .north => {
                    if (self.row == 0) return TravelError.BadPath;
                    self.*.row -= 1;
                    return .north;
                },
                .east => {
                    if (self.col == map.col_len - 1) return TravelError.BadPath;
                    self.*.col += 1;
                    return .east;
                },
                .south => {
                    if (self.row == map.row_len - 1) return TravelError.BadPath;
                    self.*.row += 1;
                    return .south;
                },
                .west => {
                    if (self.col == 0) return TravelError.BadPath;
                    self.*.col -= 1;
                    return .west;
                },
            },
            '|' => switch (traveling) {
                .north => {
                    self.*.row -= 1;
                    return .north;
                },
                .south => {
                    self.*.row += 1;
                    return .south;
                },
                else => return TravelError.BadPath,
            },
            '-' => switch (traveling) {
                .east => {
                    self.*.col += 1;
                    return .east;
                },
                .west => {
                    self.*.col -= 1;
                    return .west;
                },
                else => return TravelError.BadPath,
            },
            'L' => switch (traveling) {
                .south => {
                    self.*.col += 1;
                    return .east;
                },
                .west => {
                    self.*.row -= 1;
                    return .north;
                },
                else => return TravelError.BadPath,
            },
            'J' => switch (traveling) {
                .south => {
                    self.*.col -= 1;
                    return .west;
                },
                .east => {
                    self.*.row -= 1;
                    return .north;
                },
                else => return TravelError.BadPath,
            },
            '7' => switch (traveling) {
                .north => {
                    self.*.col -= 1;
                    return .west;
                },
                .east => {
                    self.*.row += 1;
                    return .south;
                },
                else => return TravelError.BadPath,
            },
            'F' => switch (traveling) {
                .north => {
                    self.*.col += 1;
                    return .east;
                },
                .west => {
                    self.*.row += 1;
                    return .south;
                },
                else => return TravelError.BadPath,
            },
            else => return TravelError.BadPath,
        }
    }
};
const Map = struct {
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

    pub fn deinit(self: Map) void {
        for (self.lines.items) |line| {
            line.deinit();
        }
        self.lines.deinit();
    }
};

fn findStartLocation(map: Map) Location {
    for (map.lines.items, 0..) |line, row| {
        if (std.mem.indexOf(u8, line.items, "S")) |col| {
            return Location{
                .row = row,
                .col = col,
            };
        }
    }
    unreachable;
}
