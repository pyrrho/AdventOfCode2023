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
    INPUT.SAMPLE_1 => "src/day22_sample_input.txt",
    INPUT.PRIMARY => "src/day22_input.txt",
};
const DIMENSIONS = switch (TARGET) {
    INPUT.SAMPLE_1 => .{ 3, 3, 10 },
    INPUT.PRIMARY => .{ 10, 10, 361 },
};

const EXPECTED_RESULT = switch (TARGET) {
    INPUT.SAMPLE_1 => "5",
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

    var grid = try Grid(DIMENSIONS).init(allocator);
    defer grid.deinit();

    {
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

            var coord_tokens = std.mem.tokenizeSequence(u8, buf.items, "~");
            var coord_a_tokens = std.mem.tokenizeSequence(u8, coord_tokens.next().?, ",");
            var coord_b_tokens = std.mem.tokenizeSequence(u8, coord_tokens.next().?, ",");

            const coord_a = .{
                try std.fmt.parseInt(u16, coord_a_tokens.next().?, 10),
                try std.fmt.parseInt(u16, coord_a_tokens.next().?, 10),
                try std.fmt.parseInt(u16, coord_a_tokens.next().?, 10),
            };
            const coord_b = .{
                try std.fmt.parseInt(u16, coord_b_tokens.next().?, 10),
                try std.fmt.parseInt(u16, coord_b_tokens.next().?, 10),
                try std.fmt.parseInt(u16, coord_b_tokens.next().?, 10),
            };

            try grid.insertBlockFromCoordPair(coord_a, coord_b);

            buf.clearRetainingCapacity();
        }
    }
    grid.populateSpace();
    grid.dropStuff();

    // A map of block idx -> { [block indexes above idx], [block indexes below idx] }
    var m = AutoHashMap(usize, struct { ups: ArrayList(usize), downs: ArrayList(usize) }).init(allocator);
    defer {
        var itr = m.valueIterator();
        while (itr.next()) |v| {
            v.ups.deinit();
            v.downs.deinit();
        }
        m.deinit();
    }
    for (grid.blocks.items, 0..) |block, idx| {
        var ups = ArrayList(usize).init(allocator);
        var downs = ArrayList(usize).init(allocator);

        var u_itr = block.aboveIterator();
        while (u_itr.next()) |coords| {
            if (grid.space[coords[0]][coords[1]][coords[2]]) |s| {
                if (listContains(ups, s.idx)) continue;
                try ups.append(s.idx);
            }
        }
        var b_itr = block.belowIterator();
        while (b_itr.next()) |coords| {
            if (grid.space[coords[0]][coords[1]][coords[2]]) |s| {
                if (listContains(downs, s.idx)) continue;
                try downs.append(s.idx);
            }
        }

        try m.put(idx, .{ .ups = ups, .downs = downs });
    }

    var frontier = ArrayList(usize).init(allocator);
    defer frontier.deinit();
    var falling = AutoHashMap(usize, void).init(allocator);
    defer falling.deinit();

    var total_falling: u64 = 0;

    for (grid.blocks.items, 0..) |_, next_to_fall| {
        frontier.clearRetainingCapacity();
        falling.clearRetainingCapacity();

        try frontier.append(next_to_fall);

        while (frontier.items.len > 0) {
            const idx = frontier.pop();
            try falling.put(idx, void{});

            const blocks_above = m.get(idx).?.ups.items;
            for (blocks_above) |block_above| {
                const blocks_below_block_above = m.get(block_above).?.downs.items;
                if (mapContains(falling, blocks_below_block_above)) {
                    try frontier.append(block_above);
                }
            }
        }

        total_falling += falling.count() - 1;
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        "The number of blocks that will fall is {d}\n",
        .{total_falling},
    );
}

fn listContains(l: ArrayList(usize), i: usize) bool {
    for (l.items) |e| {
        if (e == i) return true;
    }
    return false;
}

fn mapContains(m: AutoHashMap(usize, void), list: []usize) bool {
    for (list) |e| {
        if (!m.contains(e)) return false;
    }
    return true;
}

// Types
// =============================================================================

const Block = struct {
    const Self = @This();
    width: u16,
    depth: u16,
    height: u16,

    coords: [3]u16,

    // Inclusive coordinates; `.{1,0,1}, .{1,0.1}` is a single cube. `.{1,0,1},
    // .{1,2,1}` is a thre-cube line.
    pub fn initFromCoordPair(a: [3]u16, b: [3]u16) Block {
        return .{
            .width = b[0] - a[0] + 1,
            .depth = b[1] - a[1] + 1,
            .height = b[2] - a[2] + 1,
            .coords = a,
        };
    }

    pub fn x(self: Self) u16 {
        return self.coords[0];
    }
    pub fn y(self: Self) u16 {
        return self.coords[1];
    }
    pub fn z(self: Self) u16 {
        return self.coords[2];
    }

    pub fn x2(self: Self) u16 {
        return self.coords[0] + self.width - 1;
    }
    pub fn y2(self: Self) u16 {
        return self.coords[1] + self.depth - 1;
    }
    pub fn z2(self: Self) u16 {
        return self.coords[2] + self.height - 1;
    }

    pub fn compare(self: Self, other: Self) i32 {
        if (self.z2() < other.z2()) return -1;
        if (self.z2() > other.z2()) return 1;
        if (self.y() < other.y()) return -1;
        if (self.y() > other.y()) return 1;
        if (self.x() < other.x()) return -1;
        if (self.x() > other.x()) return 1;
        return 0;
    }

    pub fn iterator(self: *const Self) Iterator {
        return .{
            .b = self,
            .x = self.x(),
            .y = self.y(),
            .z = self.z(),
        };
    }

    pub fn belowIterator(self: *const Self) BelowIterator {
        return .{
            .b = self,
            .x = self.x(),
            .y = self.y(),
        };
    }

    pub fn aboveIterator(self: *const Self) AboveIterator {
        return .{
            .b = self,
            .x = self.x(),
            .y = self.y(),
        };
    }

    pub const Iterator = struct {
        b: *const Block,
        x: u16,
        y: u16,
        z: u16,

        pub fn next(it: *Iterator) ?[3]u16 {
            if (it.z > it.b.z2()) return null;

            const ret = .{ it.x, it.y, it.z };

            if (it.x < it.b.x2()) {
                it.x += 1;
            } else if (it.y < it.b.y2()) {
                it.x = it.b.x();
                it.y += 1;
            } else {
                it.x = it.b.x();
                it.y = it.b.y();
                it.z += 1;
            }
            return ret;
        }
    };

    pub const BelowIterator = struct {
        b: *const Block,
        x: u16,
        y: u16,

        pub fn next(it: *BelowIterator) ?[3]u16 {
            if (it.b.z() == 0) return null;
            if (it.y > it.b.y2()) return null;

            const ret = .{ it.x, it.y, it.b.z() - 1 };

            if (it.x < it.b.x2()) {
                it.x += 1;
            } else {
                it.x = it.b.x();
                it.y += 1;
            }
            return ret;
        }
    };

    pub const AboveIterator = struct {
        b: *const Block,
        x: u16,
        y: u16,

        pub fn next(it: *AboveIterator) ?[3]u16 {
            if (it.b.z() == DIMENSIONS[2] - 1) return null;
            if (it.y > it.b.y2()) return null;

            const ret = .{ it.x, it.y, it.b.z2() + 1 };

            if (it.x < it.b.x2()) {
                it.x += 1;
            } else {
                it.x = it.b.x();
                it.y += 1;
            }
            return ret;
        }
    };
};

fn Grid(
    comptime dimensions: [3]comptime_int,
) type {
    return struct {
        const Self = @This();

        const width = dimensions[0];
        const depth = dimensions[1];
        const height = dimensions[2];

        const Space = [width][depth][height]?struct { idx: usize, is_root: bool };

        allocator: Allocator,

        blocks: ArrayList(Block),
        space: *Space,

        pub fn init(
            allocator: Allocator,
        ) !Self {
            const space = try allocator.create(Space);
            for (space) |*x| for (x) |*y| @memset(y, null);

            return Self{
                .allocator = allocator,
                .blocks = ArrayList(Block).init(allocator),
                .space = space,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.space);
            self.blocks.deinit();
        }

        pub fn insertBlockFromCoordPair(self: *Self, a: [3]u16, b: [3]u16) !void {
            const block = Block.initFromCoordPair(a, b);
            var idx: usize = 0;
            while (idx < self.blocks.items.len and
                block.compare(self.blocks.items[idx]) > 0) : (idx += 1)
            {}

            try self.blocks.insert(idx, block);
        }

        pub fn populateSpace(self: *Self) void {
            for (self.blocks.items, 0..) |block, idx| {
                var itr = block.iterator();
                while (itr.next()) |coords| {
                    self.space[coords[0]][coords[1]][coords[2]] = .{ .idx = idx, .is_root = false };
                }

                self.space[block.x()][block.y()][block.z()].?.is_root = true;
            }
        }

        pub fn dropStuff(self: *Self) void {
            for (self.blocks.items) |*block| {
                while (!self.blockHasLowerNeighbors(block.*)) {
                    var itr = block.iterator();
                    while (itr.next()) |coords| {
                        self.space[coords[0]][coords[1]][coords[2] - 1] = self.space[coords[0]][coords[1]][coords[2]];
                        self.space[coords[0]][coords[1]][coords[2]] = null;
                    }
                    block.coords[2] -= 1;
                }
            }
        }

        fn blockHasLowerNeighbors(self: *Self, block: Block) bool {
            if (block.z() == 0) return true;

            var itr = block.belowIterator();
            while (itr.next()) |coords| {
                if (self.space[coords[0]][coords[1]][coords[2]] != null) {
                    return true;
                }
            }
            return false;
        }

        pub fn debugPrint3D(self: Self) void {
            for (0..Self.height) |a| {
                const z = Self.height - a - 1;

                std.debug.print("    ", .{});
                for (0..Self.depth) |_| std.debug.print(" ", .{});
                for (0..Self.width) |i| std.debug.print("{d} ", .{i});
                std.debug.print("\n", .{});

                for (0..Self.depth) |b| {
                    const y = Self.depth - 1 - b;
                    if (b == 0) {
                        std.debug.print("{d: >3} ", .{z});
                    } else {
                        std.debug.print("    ", .{});
                    }

                    for (0..y) |_| {
                        std.debug.print(" ", .{});
                    }

                    std.debug.print("/", .{});
                    for (0..Self.width) |x| {
                        if (self.space[x][y][z]) |s| {
                            if (s.is_root) {
                                std.debug.print("{c}/", .{'A' + @as(u8, @intCast(s.idx % 26))});
                            } else {
                                std.debug.print("{c}/", .{'a' + @as(u8, @intCast(s.idx % 26))});
                            }
                        } else {
                            std.debug.print(" /", .{});
                        }
                    }

                    std.debug.print(" {}\n", .{y});
                }
            }
            std.debug.print("\n", .{});
        }
    };
}

test "block iterators" {
    const b1 = Block.initFromCoordPair(.{ 1, 0, 1 }, .{ 4, 0, 1 });
    var it1 = b1.iterator();
    const b2 = Block.initFromCoordPair(.{ 1, 0, 1 }, .{ 1, 2, 1 });
    var it2 = b2.iterator();
    const b3 = Block.initFromCoordPair(.{ 1, 0, 1 }, .{ 1, 0, 2 });
    var it3 = b3.iterator();

    try std.testing.expectEqualDeep([_]u16{ 1, 0, 1 }, it1.next().?);
    try std.testing.expectEqualDeep([_]u16{ 2, 0, 1 }, it1.next().?);
    try std.testing.expectEqualDeep([_]u16{ 3, 0, 1 }, it1.next().?);
    try std.testing.expectEqualDeep([_]u16{ 4, 0, 1 }, it1.next().?);
    try std.testing.expect(it1.next() == null);

    try std.testing.expectEqualDeep([_]u16{ 1, 0, 1 }, it2.next().?);
    try std.testing.expectEqualDeep([_]u16{ 1, 1, 1 }, it2.next().?);
    try std.testing.expectEqualDeep([_]u16{ 1, 2, 1 }, it2.next().?);
    try std.testing.expect(it2.next() == null);

    try std.testing.expectEqualDeep([_]u16{ 1, 0, 1 }, it3.next().?);
    try std.testing.expectEqualDeep([_]u16{ 1, 0, 2 }, it3.next().?);
    try std.testing.expect(it3.next() == null);
}
test "block below iterators" {
    const b1 = Block.initFromCoordPair(.{ 1, 0, 1 }, .{ 4, 0, 1 });
    var it1 = b1.belowIterator();
    const b2 = Block.initFromCoordPair(.{ 1, 0, 1 }, .{ 1, 2, 1 });
    var it2 = b2.belowIterator();
    const b3 = Block.initFromCoordPair(.{ 1, 0, 1 }, .{ 1, 0, 2 });
    var it3 = b3.belowIterator();
    const b4 = Block.initFromCoordPair(.{ 1, 0, 0 }, .{ 4, 0, 0 });
    var it4 = b4.belowIterator();

    try std.testing.expectEqualDeep([_]u16{ 1, 0, 0 }, it1.next().?);
    try std.testing.expectEqualDeep([_]u16{ 2, 0, 0 }, it1.next().?);
    try std.testing.expectEqualDeep([_]u16{ 3, 0, 0 }, it1.next().?);
    try std.testing.expectEqualDeep([_]u16{ 4, 0, 0 }, it1.next().?);
    try std.testing.expect(it1.next() == null);

    try std.testing.expectEqualDeep([_]u16{ 1, 0, 0 }, it2.next().?);
    try std.testing.expectEqualDeep([_]u16{ 1, 1, 0 }, it2.next().?);
    try std.testing.expectEqualDeep([_]u16{ 1, 2, 0 }, it2.next().?);
    try std.testing.expect(it2.next() == null);

    try std.testing.expectEqualDeep([_]u16{ 1, 0, 0 }, it3.next().?);
    try std.testing.expect(it3.next() == null);

    try std.testing.expect(it4.next() == null);
}
test "block above iterators" {
    const b1 = Block.initFromCoordPair(.{ 1, 0, 1 }, .{ 4, 0, 1 });
    var it1 = b1.aboveIterator();
    const b2 = Block.initFromCoordPair(.{ 1, 0, 1 }, .{ 1, 2, 1 });
    var it2 = b2.aboveIterator();
    const b3 = Block.initFromCoordPair(.{ 1, 0, 1 }, .{ 1, 0, 2 });
    var it3 = b3.aboveIterator();
    const b4 = Block.initFromCoordPair(.{ 1, 0, DIMENSIONS[2] - 1 }, .{ 4, 0, DIMENSIONS[2] - 1 });
    var it4 = b4.aboveIterator();

    try std.testing.expectEqualDeep([_]u16{ 1, 0, 2 }, it1.next().?);
    try std.testing.expectEqualDeep([_]u16{ 2, 0, 2 }, it1.next().?);
    try std.testing.expectEqualDeep([_]u16{ 3, 0, 2 }, it1.next().?);
    try std.testing.expectEqualDeep([_]u16{ 4, 0, 2 }, it1.next().?);
    try std.testing.expect(it1.next() == null);

    try std.testing.expectEqualDeep([_]u16{ 1, 0, 2 }, it2.next().?);
    try std.testing.expectEqualDeep([_]u16{ 1, 1, 2 }, it2.next().?);
    try std.testing.expectEqualDeep([_]u16{ 1, 2, 2 }, it2.next().?);
    try std.testing.expect(it2.next() == null);

    try std.testing.expectEqualDeep([_]u16{ 1, 0, 3 }, it3.next().?);
    try std.testing.expect(it3.next() == null);

    try std.testing.expect(it4.next() == null);
}
