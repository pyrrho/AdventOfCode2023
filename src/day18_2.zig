const std = @import("std");
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

const U64_MAX = std.math.maxInt(u64);

const SAMPLE = true;
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
            var t: []const u8 = undefined;

            // I assume we're discarding the non-"color" input?
            t = tokens.next().?;
            t = tokens.next().?;

            t = tokens.next().?;
            const steps = try std.fmt.parseInt(i32, t[2..7], 16);
            const direction = try Direction.fromDec(t[7]);

            try plan_builder.append(
                PlanStep{
                    .direction = direction,
                    .steps = steps,
                },
            );
            buf.clearRetainingCapacity();
        }

        plan = try plan_builder.toOwnedSlice();
    }
    defer allocator.free(plan);

    // Apply the shoelace formula
    // --------------------------
    var x1: i64 = 0;
    var y1: i64 = 0;
    var x2: i64 = 0;
    var y2: i64 = 0;
    var area: i64 = 0;
    var circumference: i64 = 0;
    for (plan) |s| {
        circumference += @abs(s.steps);

        switch (s.direction) {
            .East => x2 += s.steps,
            .South => y2 += s.steps,
            .West => x2 -= s.steps,
            .North => y2 -= s.steps,
        }

        area += (x1 * y2) - (x2 * y1);
        x1 = x2;
        y1 = y2;
    }

    area += circumference;
    area = @divExact(area, 2);
    area += 1; // TODO: What is this about? Is the circumference too small or something?

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Dug cells: {d}\n", .{area});
}

// Types
// =============================================================================

const Direction = enum(usize) {
    East,
    South,
    West,
    North,

    pub fn fromDec(c: u8) !Direction {
        return switch (c) {
            '0' => .East,
            '1' => .South,
            '2' => .West,
            '3' => .North,
            else => @panic("Invalid direction character"),
        };
    }
};

const PlanStep = struct {
    direction: Direction,
    steps: i32,
};

const Point = struct {
    x: i64,
    y: i64,
};
