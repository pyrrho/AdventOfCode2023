const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const TARGET = INPUT.SAMPLE_1;
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

    grid.debugPrint3D();
    std.debug.print("\n", .{});
    grid.dropStuff();

    grid.debugPrint3D();
}

// Types
// =============================================================================

const Block = struct {
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
};

fn Grid(
    comptime dimensions: [3]comptime_int,
) type {
    return struct {
        const Self = @This();

        const width = dimensions[0];
        const depth = dimensions[1];
        const height = dimensions[2];

        const Space = [width][depth][height]?usize;

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
            const block_idx = self.blocks.items.len;
            try self.blocks.append(Block.initFromCoordPair(a, b));
            const block = self.blocks.items[block_idx];

            for (0..block.width) |x| {
                for (0..block.depth) |y| {
                    for (0..block.height) |z| {
                        self.space[a[0] + x][a[1] + y][a[2] + z] = block_idx;
                    }
                }
            }
        }

        pub fn dropStuff(self: *Self) void {
            for (0..Self.height) |z| {
                for (0..Self.depth) |y| {
                    for (0..Self.width) |x| {
                        if (self.space[x][y][z]) |idx| {
                            const block = &self.blocks.items[idx];

                            if (block.*.coords[0] != x or block.*.coords[1] != y or block.*.coords[2] != z) continue;

                            while (block.coords[2] > 0 and !self.blockHasLowerNeighbors(block.*)) {
                                for (block.coords[2]..block.coords[2] + block.height) |b_z| {
                                    for (block.coords[1]..block.coords[1] + block.depth) |b_y| {
                                        for (block.coords[0]..block.coords[0] + block.width) |b_x| {
                                            self.space[b_x][b_y][b_z] = null;
                                            self.space[b_x][b_y][b_z - 1] = idx;
                                        }
                                    }
                                }
                                block.coords[2] -= 1;
                            }
                        }
                    }
                }
            }
        }

        fn blockHasLowerNeighbors(self: *Self, block: Block) bool {
            for (0..block.width) |b_x| {
                for (0..block.depth) |b_y| {
                    const x = block.coords[0] + b_x;
                    const y = block.coords[1] + b_y;
                    const z = block.coords[2] - 1;
                    if (self.space[x][y][z] != null) {
                        return true;
                    }
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

                for (0..Self.depth) |y| {
                    if (y == Self.depth - 1) {
                        std.debug.print("{d: >3} ", .{z});
                    } else {
                        std.debug.print("    ", .{});
                    }

                    for (0..Self.depth - 1 - y) |_| {
                        std.debug.print(" ", .{});
                    }

                    std.debug.print("/", .{});
                    for (0..Self.width) |x| {
                        if (self.space[x][y][z]) |idx| {
                            std.debug.print("{c}/", .{'a' + @as(u8, @intCast(idx % 26))});
                        } else {
                            std.debug.print(" /", .{});
                        }
                    }

                    std.debug.print(" {}\n", .{Self.depth - 1 - y});
                }
            }
            std.debug.print("\n", .{});
        }
    };
}

// const Grid = struct {
//     const Self = @This();

//     allocator: Allocator,

//     width: usize,
//     depth: usize,
//     height: usize,

//     blocks: []*Block,
//     space: [][][]?*Block, // This smells wrong...

//     pub fn initFromBlocks(
//     ) !Grid {
//         return Grid{
//             .allocator = allocator,
//         };
//     }
// };
