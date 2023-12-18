const std = @import("std");
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

const U64_MAX = std.math.maxInt(u64);

const SAMPLE = false;
const FILE_PATH = if (SAMPLE) "src/day18_sample_input.txt" else "src/day18_input.txt";

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
    var plan: []PlanStep = undefined;
    {
        var plan_builder = ArrayList(PlanStep).init(allocator);
        var buf = ArrayList(u8).init(allocator);
        defer buf.deinit();
        const writer = buf.writer();

        while (true) {
            in_stream.streamUntilDelimiter(writer, '\n', null) catch |err| switch (err) {
                error.EndOfStream => break,
                else => {
                    buf.deinit();
                    return err;
                },
            };

            var tokens = std.mem.tokenizeSequence(u8, buf.items, " ");

            var t = tokens.next().?;
            const direction = try Direction.fromChar(t[0]);

            t = tokens.next().?;
            const steps = try std.fmt.parseInt(u8, t, 10);

            t = tokens.next().?;
            const color = try allocator.alloc(u8, 6);
            @memcpy(color, t[2..8]);

            try plan_builder.append(
                PlanStep{
                    .direction = direction,
                    .steps = steps,
                    .color = color,
                },
            );
            buf.clearRetainingCapacity();
        }

        plan = try plan_builder.toOwnedSlice();
    }
    defer {
        for (plan) |s| {
            allocator.free(s.color);
        }
        allocator.free(plan);
    }

    // Turn the plan into spacial points
    // ---------------------------------
    var points = ArrayList(Point).init(allocator);
    defer points.deinit();
    var min_x: i64 = std.math.maxInt(i64);
    var max_x: i64 = 0;
    var min_y: i64 = std.math.maxInt(i64);
    var max_y: i64 = 0;
    {
        var x: i64 = 0;
        var y: i64 = 0;

        try points.append(Point{ .x = x, .y = y });
        for (plan) |s| {
            switch (s.direction) {
                .East => x += s.steps,
                .South => y += s.steps,
                .West => x -= s.steps,
                .North => y -= s.steps,
            }

            try points.append(Point{ .x = x, .y = y });

            min_x = @min(min_x, x);
            max_x = @max(max_x, x);
            min_y = @min(min_y, y);
            max_y = @max(max_y, y);
        }
    }
    const width: usize = @intCast(max_x - min_y + 1);
    const height: usize = @intCast(max_y - min_y + 1);

    // Normalize the points s.t. none are < 0
    // --------------------------------------
    for (points.items) |*p| {
        p.x -= min_x;
        p.y -= min_y;
    }

    // Turn the spacial points into a grid
    // -----------------------------------
    var flat_grid = try allocator.alloc(FillType, height * width);
    @memset(flat_grid, FillType.level);

    var grid: [][]FillType = try allocator.alloc([]FillType, height);
    for (0..height) |y| {
        grid[y] = flat_grid[y * width .. (y + 1) * width];
    }

    defer allocator.free(grid);
    defer allocator.free(flat_grid);

    // Run the edges of the grid
    // -------------------------
    {
        var x: usize = @intCast(points.items[0].x);
        var y: usize = @intCast(points.items[0].y);
        var prev_dir = plan[plan.len - 1].direction;

        for (plan) |s| {
            switch (s.direction) {
                .East => {
                    grid[y][x] = FillType.fromDirections(prev_dir, .East);
                    for (1..s.steps) |_| {
                        x += 1;
                        grid[y][x] = FillType.dug;
                    }
                    x += 1;
                },
                .South => {
                    grid[y][x] = FillType.fromDirections(prev_dir, .South);
                    for (1..s.steps) |_| {
                        y += 1;
                        grid[y][x] = FillType.dug;
                    }
                    y += 1;
                },
                .West => {
                    grid[y][x] = FillType.fromDirections(prev_dir, .West);
                    for (1..s.steps) |_| {
                        x -= 1;
                        grid[y][x] = FillType.dug;
                    }
                    x -= 1;
                },
                .North => {
                    grid[y][x] = FillType.fromDirections(prev_dir, .North);
                    for (1..s.steps) |_| {
                        y -= 1;
                        grid[y][x] = FillType.dug;
                    }
                    y -= 1;
                },
            }
            prev_dir = s.direction;
        }
    }

    // // Print the grid
    // // --------------
    // for (grid) |row| {
    //     for (row) |cell| {
    //         const c = cell.toChar();
    //         std.debug.print("{c}", .{c});
    //     }
    //     std.debug.print("\n", .{});
    // }
    // std.debug.print("\n", .{});

    // Fill the grid
    // -------------
    var dug_cells: u64 = 0;

    for (grid, 0..) |row, y| {
        var in_pit = false;
        var last = FillType.level;

        for (row, 0..) |cell, x| {
            switch (cell) {
                .level => {
                    last = .level;
                },
                .dug => {
                    if (last == .level) {
                        in_pit = !in_pit;
                    }
                },
                .SouthEast => {
                    last = .SouthEast;
                },
                .NorthEast => {
                    last = .NorthEast;
                },
                .SouthWest => {
                    if (last == .NorthEast) {
                        in_pit = !in_pit;
                        last = .level;
                    }
                },
                .NorthWest => {
                    if (last == .SouthEast) {
                        in_pit = !in_pit;
                        last = .level;
                    }
                },
            }

            if (in_pit and grid[y][x] == .level) {
                grid[y][x] = .dug;
            }

            if (grid[y][x] != .level) {
                dug_cells += 1;
            }
        }
    }

    // Print the grid
    // --------------
    for (grid) |row| {
        for (row) |cell| {
            const c = cell.toChar();
            std.debug.print("{c}", .{c});
        }
        std.debug.print("\n", .{});
    }
    std.debug.print("\n", .{});

    // Output
    // ------
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Dug cells: {d}\n", .{dug_cells});
}

// Types
// =============================================================================

const Direction = enum(usize) {
    East,
    South,
    West,
    North,

    pub fn fromChar(c: u8) !Direction {
        switch (c) {
            'R' => return .East,
            'D' => return .South,
            'L' => return .West,
            'U' => return .North,
            else => @panic("Invalid direction character"),
        }
    }
};

const PlanStep = struct {
    direction: Direction,
    steps: u8,
    color: []const u8,
};

const Point = struct {
    x: i64,
    y: i64,
};

const FillType = enum(u4) {
    level = 0,
    dug = 1,
    SouthEast = 2,
    SouthWest = 3,
    NorthWest = 4,
    NorthEast = 5,

    pub fn toChar(self: FillType) u8 {
        switch (self) {
            .level => return '.',
            .dug => return '#',
            .SouthEast => return 'F',
            .SouthWest => return '7',
            .NorthWest => return 'J',
            .NorthEast => return 'L',
        }
    }

    pub fn fromDirections(prev: Direction, next: Direction) FillType {
        switch (prev) {
            .West => switch (next) {
                .South => return .SouthEast,
                .North => return .NorthEast,
                else => @panic("Invalid direction"),
            },
            .South => switch (next) {
                .East => return .NorthEast,
                .West => return .NorthWest,
                else => @panic("Invalid direction"),
            },
            .East => switch (next) {
                .North => return .NorthWest,
                .South => return .SouthWest,
                else => @panic("Invalid direction"),
            },
            .North => switch (next) {
                .West => return .SouthWest,
                .East => return .SouthEast,
                else => @panic("Invalid direction"),
            },
        }
    }
};
