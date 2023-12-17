const std = @import("std");
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

const SAMPLE = false;
const FILE_PATH = if (SAMPLE) "src/day16_sample_input.txt" else "src/day16_input.txt";
// The number and span of rows in the input files.
// FIXME: I'd like to remove this variable, and allow the whole program to be
//        executable without prior knowledge of the input file.
const Z = if (SAMPLE) 10 else 110;

const Direction = enum(usize) {
    North,
    South,
    West,
    East,
};

const FlatEnergyGrid = [Z * Z]bool;

// 2D accessor for the FlatEnergyGrid.
// TODO: I can't believe this works... allocates a fixed-length array of slices
//       on the stack, that allows for mutation of the underlying memory?
//       This a feature or a bug?
const EnergyGrid = [Z][]bool;
fn GridFromFlat(flat: *FlatEnergyGrid) EnergyGrid {
    var eg: EnergyGrid = undefined;
    for (0..Z) |y| {
        eg[y] = flat.*[y * Z .. (y + 1) * Z];
    }
    return eg;
}

const EMPTY_GRID = std.mem.zeroes(FlatEnergyGrid);

const Memo = AutoHashMap(MemoKey, MemoValue);
const MemoKey = struct {
    x: usize,
    y: usize,
};
// The Edges that make up a Memo Value are stored in a 4-element array, intended
// to be indexed via `@intFromEnum(Direction.*)`, such that the e.g. Northern-
// traveling edge can be consistently accessed, but all edges can be iterated
// in a for-loop.
const MemoValue = [4]?MemoEdge;
const MemoEdge = struct {
    grid: ?*FlatEnergyGrid,
    next: ?MemoKey,
};

const Walker = struct { x: usize, y: usize, direction: Direction };

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
    // =========================================================================
    var lines: [][]const u8 = undefined;
    {
        var lines_builder = ArrayList([]const u8).init(allocator);
        var line = ArrayList(u8).init(allocator);
        const writer = line.writer();

        while (true) {
            in_stream.streamUntilDelimiter(writer, '\n', 1024) catch |err| switch (err) {
                error.EndOfStream => break,
                else => {
                    line.deinit();
                    lines_builder.deinit();
                    return err;
                },
            };
            try lines_builder.append(try line.toOwnedSlice());
        }

        lines = try lines_builder.toOwnedSlice();
    }
    defer {
        for (lines) |l| {
            allocator.free(l);
        }
        defer allocator.free(lines);
    }

    // Generate the bottom-up memo
    // =========================================================================
    // This flag was _way_ more useful when I was generating the memo in main,
    // rather than in a helper method.
    var memo = try generateBottomUpMemo(lines, allocator);
    defer {
        var itr = memo.iterator();
        while (itr.next()) |entry| {
            for (entry.value_ptr.*) |edge| {
                if (edge) |e| if (e.grid) |g| allocator.free(g);
            }
        }
        memo.deinit();
    }

    // Print a bunch of stuff
    // =========================================================================
    // Or don't. I'm a comment, not a cop.
    // {
    //     var itr = memo.iterator();
    //     const grid = try allocator.create(FlatEnergyGrid);
    //     defer allocator.free(grid);

    //     while (itr.next()) |entry| {
    //         @memset(grid, false);

    //         const key = entry.key_ptr.*;
    //         const val = entry.value_ptr.*;

    //         std.debug.print("key: ({}, {}) '{c}'\n", .{ key.x, key.y, lines[key.y][key.x] });

    //         if (val.north) |n| if (n.grid) |g| overlayGrids(grid, g.*);
    //         if (val.south) |s| if (s.grid) |g| overlayGrids(grid, g.*);
    //         if (val.west) |w| if (w.grid) |g| overlayGrids(grid, g.*);
    //         if (val.east) |e| if (e.grid) |g| overlayGrids(grid, g.*);

    //         printGrid(GridFromFlat(grid), lines);
    //         std.debug.print("\n", .{});
    //     }
    // }

    // Generate Seed walkers
    // =========================================================================
    // Each is at a unique location on the edge of the grid, and is facing
    // toward the center of the grid.
    // And this is compile time! What fun!

    const moving_north = init_north: {
        var ret: [Z]Walker = undefined;
        for (&ret, 0..Z) |*v, i| {
            v.* = Walker{ .direction = .North, .x = i, .y = Z - 1 };
        }
        break :init_north ret;
    };
    const moving_south = init_south: {
        var ret: [Z]Walker = undefined;
        for (&ret, 0..Z) |*v, i| {
            v.* = Walker{ .direction = .South, .x = i, .y = 0 };
        }
        break :init_south ret;
    };
    const moving_east = init_east: {
        var ret: [Z]Walker = undefined;
        for (&ret, 0..Z) |*v, i| {
            v.* = Walker{ .direction = .East, .x = 0, .y = i };
        }
        break :init_east ret;
    };
    const moving_west = init_west: {
        var ret: [Z]Walker = undefined;
        for (&ret, 0..Z) |*v, i| {
            v.* = Walker{ .direction = .West, .x = Z - 1, .y = i };
        }
        break :init_west ret;
    };
    var seeds = moving_east ++ moving_north ++ moving_west ++ moving_south;

    // Walk the seeds
    // =========================================================================
    // Looking for the starting location that energizes the most tiles using a
    // pretty simple seen set/stack array to walk the graph.
    var energized_tiles: u64 = 0;

    // NB. These are all resources that can be reused. Just zero them out
    //     at the start of every loop, rather than allocating new ones.
    var seen_nodes = AutoHashMap(MemoKey, void).init(allocator);
    var stack = ArrayList(MemoKey).init(allocator);
    defer seen_nodes.deinit();
    defer stack.deinit();

    const flat_grid = try allocator.create(FlatEnergyGrid);
    var grid = GridFromFlat(flat_grid);
    defer allocator.free(flat_grid);

    for (&seeds) |*seed| {
        @memset(flat_grid, false);
        seen_nodes.clearRetainingCapacity();
        stack.clearRetainingCapacity();

        // Manually walk to the first node (if any) from the seed.
        // FIXME: This may result in some duplicate work if the first node
        //        bounces the walker back in the direction the seed came from.
        //        Not doing that would require treating the off-the-edge nodes
        //        our see walkers are "coming from" to be considered nodes. Not
        //        sure I want to figure out how to track that.
        grid[seed.y][seed.x] = true;
        if (walkToNextNode(lines, seed, grid)) |first| {
            try stack.append(first);
        }

        while (stack.items.len > 0) {
            const key = stack.pop();
            const edges = memo.get(key).?;
            for (edges) |edge| {
                if (edge) |e| {
                    if (e.grid) |g| {
                        overlayGrids(flat_grid, g.*);
                    }
                    if (e.next) |n| {
                        if (!seen_nodes.contains(n)) {
                            try stack.append(n);
                            try seen_nodes.put(n, void{});
                        }
                    }
                }
            }
        }

        energized_tiles = @max(energized_tiles, countEnergizedCells(flat_grid.*));
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Energized tiles: {}\n", .{energized_tiles});
}

fn generateBottomUpMemo(lines: [][]const u8, allocator: std.mem.Allocator) !Memo {
    const grid_height = lines.len;
    const grid_width = lines[0].len;

    var memo = Memo.init(allocator);

    var y: usize = 0;
    while (y < grid_height) : (y += 1) {
        var x: usize = 0;
        while (x < grid_width) : (x += 1) {
            const tile = lines[y][x];
            if (tile == '.' or tile == '\\' or tile == '/') continue;

            const key = MemoKey{ .x = x, .y = y };
            // FIXME: This is a premature optimization. It would be cool to build bi-directional
            //        bindings simultaneously. Ex; walk `.North` from node A to to B, populate the
            //        `.north` edge for node A, then populate the `.south` edge for node B.
            //        There's a lot of complexity there, though, not the least of which is a
            //        potential double-free when releasing the `memo`'s memory (also my example is
            //        wrong b/c of turns). So for the memoent, we expect to never hit this branch.
            const val = blk: {
                if (memo.getPtr(key)) |v| {
                    std.debug.assert(false);
                    break :blk v;
                }
                try memo.put(key, MemoValue{ null, null, null, null });
                break :blk memo.getPtr(key).?;
            };

            switch (tile) {
                '|' => {
                    if (val.*[@intFromEnum(Direction.North)] == null) {
                        val.*[@intFromEnum(Direction.North)] = try walkEdge(
                            Walker{ .x = x, .y = y, .direction = .North },
                            lines,
                            allocator,
                        );
                    }
                    if (val.*[@intFromEnum(Direction.South)] == null) {
                        val.*[@intFromEnum(Direction.South)] = try walkEdge(
                            Walker{ .x = x, .y = y, .direction = .South },
                            lines,
                            allocator,
                        );
                    }
                },
                '-' => {
                    if (val.*[@intFromEnum(Direction.West)] == null) {
                        val.*[@intFromEnum(Direction.West)] = try walkEdge(
                            Walker{ .x = x, .y = y, .direction = .West },
                            lines,
                            allocator,
                        );
                    }
                    if (val.*[@intFromEnum(Direction.East)] == null) {
                        val.*[@intFromEnum(Direction.East)] = try walkEdge(
                            Walker{ .x = x, .y = y, .direction = .East },
                            lines,
                            allocator,
                        );
                    }
                },
                else => @panic("invalid input"),
            }
        }
    }

    return memo;
}

// TODO: We're accepting a `Walker` here as a convenience; we need to copy
//       ("copy"?) it to make it mutable for `walkToNextNode`. I have a feeling
//       that the copy can be elided in the case that the we instantiate the
//       Walker in the parameter expression of this function. Do some digging.
//       figure out if that's happening when we compile in a non-debug mode.
//       Or maybe there's a way to pass a paramter by value and signal that it
//       should be mutable?
fn walkEdge(
    walker: Walker,
    lines: [][]const u8,
    allocator: std.mem.Allocator,
) !MemoEdge {
    const flat_grid = try allocator.create(FlatEnergyGrid);
    @memset(flat_grid, false);
    const grid = GridFromFlat(flat_grid);

    var _walker = walker;

    // NB. side-effects `flat_grid` (via `grid`).
    const next = walkToNextNode(lines, &_walker, grid);

    if (std.mem.eql(bool, flat_grid, &EMPTY_GRID)) {
        allocator.free(flat_grid);
        return MemoEdge{ .grid = null, .next = null };
    } else {
        return MemoEdge{ .grid = flat_grid, .next = next };
    }

    // if (next == null) break :north;
    //
    // // FIXME: This optimization is going to lead to double-frees. Is there a
    // //        weak pointer in zig?
    // //        Also, we might be building spurious links that will never be
    // //        traversed (ex; adding a `.south` to a '-' node).
    // if (memo.getPtr(next.?)) |nv| {
    //     if (nv.*.south == null) {
    //         nv.*.south = MemoEdge{ .grid = flat_grid, .next = key };
    //     }
    // } else {
    //     const nk = MemoKey{ .x = next.?.x, .y = next.?.y };
    //     const nv = MemoValue{
    //         .north = null,
    //         .east = null,
    //         .south = MemoEdge{ .grid = flat_grid, .next = key },
    //         .west = null,
    //     };

    //     try memo.put(nk, nv);
    // }

}

fn walkToNextNode(lines: [][]const u8, walker: *Walker, grid: EnergyGrid) ?MemoKey {
    const grid_width = lines[0].len;
    const grid_height = lines.len;
    while (true) {
        stepWalker(walker, grid_width, grid_height) catch return null;
        grid[walker.y][walker.x] = true;
        const tile = lines[walker.y][walker.x];
        switch (tile) {
            '.' => {},
            '\\' => switch (walker.direction) {
                .North => walker.direction = .West,
                .South => walker.direction = .East,
                .West => walker.direction = .North,
                .East => walker.direction = .South,
            },
            '/' => switch (walker.direction) {
                .North => walker.direction = .East,
                .South => walker.direction = .West,
                .West => walker.direction = .South,
                .East => walker.direction = .North,
            },
            '|', '-' => return .{ .x = walker.x, .y = walker.y },
            else => @panic("invalid input"),
        }
    }
}

const TravelError = error{
    EndOfGrid,
};
fn stepWalker(walker: *Walker, grid_width: usize, grid_height: usize) TravelError!void {
    switch (walker.direction) {
        .North => {
            if (walker.y == 0) return TravelError.EndOfGrid;
            walker.y -= 1;
        },
        .South => {
            if (walker.y == grid_height - 1) return TravelError.EndOfGrid;
            walker.y += 1;
        },
        .West => {
            if (walker.x == 0) return TravelError.EndOfGrid;
            walker.x -= 1;
        },
        .East => {
            if (walker.x == grid_width - 1) return TravelError.EndOfGrid;
            walker.x += 1;
        },
    }
}

fn overlayGrids(grid: *FlatEnergyGrid, overlay: FlatEnergyGrid) void {
    var i: usize = 0;
    while (i < grid.*.len) {
        grid.*[i] = grid.*[i] or overlay[i];
        i += 1;
    }
}

fn countEnergizedCells(grid: FlatEnergyGrid) u64 {
    var ret: u64 = 0;
    for (grid) |tile| {
        if (tile) ret += 1;
    }
    return ret;
}

fn printGrid(grid: EnergyGrid, lines: [][]const u8) void {
    for (grid, 0..) |row, y| {
        std.debug.print("{d}: ", .{y});
        for (row, 0..) |tile, x| {
            std.debug.print("{c}", .{if (tile) '#' else lines[y][x]});
        }
        std.debug.print("\n", .{});
    }
    std.debug.print("   0123456789\n", .{});
}
