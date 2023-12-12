const std = @import("std");
const ArrayList = std.ArrayList;
const InputMemo = std.HashMap(Input, u64, InputContext, std.hash_map.default_max_load_percentage);

const Input = struct {
    line: []const u8,
    current_run: u8,
    runs: []const u8,
};

// Lifting from hash_map.zig. Fun stuff?
pub const InputContext = struct {
    pub fn hash(self: @This(), s: Input) u64 {
        _ = self;
        return std.hash.Wyhash.hash(0, std.mem.asBytes(&s));
    }
    pub fn eql(self: @This(), a: Input, b: Input) bool {
        _ = self;
        return a.current_run == b.current_run and
            std.mem.eql(u8, a.line, b.line) and
            std.mem.eql(u8, a.runs, b.runs);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("MEMORY LEAK");
    }

    const file = try std.fs.cwd().openFile("src/day12_input.txt", .{});
    var buf_reader = std.io.bufferedReader(file.reader());
    const in_stream = buf_reader.reader();

    // Capture all lines into an Array List
    var input = ArrayList(Input).init(allocator);
    defer {
        for (input.items) |e| {
            allocator.free(e.line);
            allocator.free(e.runs);
        }
        input.deinit();
    }

    var buf = ArrayList(u8).init(allocator);
    defer buf.deinit();

    while (true) {
        in_stream.readUntilDelimiterArrayList(&buf, '\n', 1024) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        var tokens = std.mem.tokenizeSequence(u8, buf.items, " ");
        const line = try std.mem.Allocator.dupe(allocator, u8, tokens.next().?);

        var runs = ArrayList(u8).init(allocator);
        var num_tokens = std.mem.tokenizeSequence(u8, tokens.next().?, ",");
        while (num_tokens.next()) |token| {
            const num = try std.fmt.parseInt(u8, token, 10);
            try runs.append(num);
        }

        try input.append(Input{
            .line = line,
            .current_run = 0,
            .runs = try runs.toOwnedSlice(),
        });
    }

    var memo = InputMemo.init(allocator);
    var gc = ArrayList([]const u8).init(allocator);
    defer {
        memo.deinit();
        for (gc.items) |e| {
            allocator.free(e);
        }
        gc.deinit();
    }

    const stdout = std.io.getStdOut().writer();

    var arrangements: u64 = 0;
    for (input.items) |e| {
        const a = try getArrangements(e, &memo, &gc, allocator);

        try stdout.print("'{s}' (", .{e.line});
        try stdout.print("{}", .{e.runs[0]});
        for (e.runs[1..]) |run| {
            try stdout.print(", {}", .{run});
        }
        try stdout.print("): {}\n", .{a});

        arrangements += a;
    }

    try stdout.print("Arrangements: {}\n", .{arrangements});
}

fn getArrangements(
    input: Input,
    memo: *InputMemo,
    gc: *ArrayList([]const u8),
    allocator: std.mem.Allocator,
) !u64 {
    if (memo.get(input)) |arrangements| {
        return arrangements;
    }

    var i: usize = 0;
    var r_i: usize = 0;
    var run: u8 = input.current_run;
    while (true) {
        const at_last_run = r_i == input.runs.len;
        const last_run_done = at_last_run and run == 0;

        if (i == input.line.len) {
            return if (last_run_done) 1 else 0;
        }

        const c = input.line[i];

        switch (c) {
            '.' => {
                if (run != 0) {
                    return 0;
                }

                const run_len = (std.mem.indexOfAnyPos(u8, input.line, i, "#?") orelse input.line.len) - i;
                i += run_len;

                continue;
            },
            '#' => {
                if (run == 0) {
                    if (r_i == input.runs.len) {
                        return 0;
                    }
                    run = input.runs[r_i];
                    r_i += 1;
                }

                const run_len = (std.mem.indexOfAnyPos(u8, input.line, i, ".?") orelse input.line.len) - i;
                if (run_len > run) {
                    return 0;
                }

                run -= @as(u8, @intCast(run_len));
                i += run_len;

                if (run == 0 and i < input.line.len and input.line[i] == '?') {
                    i += 1;
                }

                continue;
            },
            '?' => {
                const run_len = (std.mem.indexOfAnyPos(u8, input.line, i, ".#") orelse input.line.len) - i;

                // If we're in the middle of a run, we have no choice but to continue it.
                if (run != 0) {
                    const steps = @min(run, run_len);
                    run -= steps;
                    i += steps;

                    // If this finishes the run, either the next char is
                    // - Past the end of `input.line`; the sequence is finished.
                    // - A '.', which is a valid sequenece; continue as normal.
                    // - A '#', which is an invalid sequence; terminate with 0 arrangements.
                    // - A '?' that needs to be converted into a '.'; skip the next char and continue.
                    if (run == 0 and i < input.line.len) {
                        const next_char = input.line[i];
                        if (next_char == '#') {
                            return 0;
                        }
                        if (next_char == '?') {
                            i += 1;
                        }
                    }
                    continue;
                }

                // If there are no more runs, we have no choice but to insert `.`s.
                if (last_run_done) {
                    i += run_len;
                    continue;
                }

                // Otherwise, we can either insert a single '.' ...
                const inserting_dot = try getArrangements(
                    Input{
                        .line = input.line[i + 1 ..],
                        .current_run = 0,
                        .runs = input.runs[r_i..],
                    },
                    memo,
                    gc,
                    allocator,
                );

                // ... or insert a single '#'s.
                const new_run = input.runs[r_i];
                const new_runs = try std.mem.Allocator.dupe(allocator, u8, input.runs[r_i + 1 ..]);
                try gc.append(new_runs);

                const inserting_q = try getArrangements(
                    Input{
                        .line = input.line[i..],
                        .current_run = new_run,
                        .runs = new_runs,
                    },
                    memo,
                    gc,
                    allocator,
                );

                // Aggregate and return
                const arrangements = inserting_dot + inserting_q;
                try memo.put(input, arrangements);
                return arrangements;
            },
            else => @panic("Invalid input character"),
        }
    }
}

// fn getArrangements2(
//     input: Input,
//     memo: *InputMemo,
//     gc: *ArrayList([]const u8),
//     allocator: std.mem.Allocator,
// ) !u64 {
//     if (memo.get(input)) |arrangements| {
//         return arrangements;
//     }

//     const next_char = input.line[0];
//     switch (next_char) {
//         '.' => {
//             const run_length = std.mem.indexOfAny(u8, input.line, "?#") orelse return 1;
//             const arrangements = try getArrangements(
//                 Input{
//                     .line = input.line[run_length..],
//                     .nums = input.nums,
//                 },
//                 memo,
//                 gc,
//                 allocator,
//             );
//             try memo.put(input, arrangements);
//             return arrangements;
//         },
//         '#' => {
//             const run_length = std.mem.indexOfAny(u8, input.line, ".?") orelse return 1;
//             if (input.nums[0] - run_length == 0) {
//                 const arrangements = try getArrangements(
//                     Input{
//                         .line = input.line[run_length..],
//                         .nums = input.nums[1..],
//                     },
//                     memo,
//                     gc,
//                     allocator,
//                 );
//                 try memo.put(input, arrangements);
//                 return arrangements;
//             }

//             var nums = try std.mem.Allocator.dupe(allocator, u8, input.nums);
//             nums[0] -= @as(u8, @intCast(run_length));
//             try gc.append(nums);

//             const arrangements = try getArrangements(
//                 Input{
//                     .line = input.line[run_length..],
//                     .nums = nums,
//                 },
//                 memo,
//                 gc,
//                 allocator,
//             );
//             try memo.put(input, arrangements);
//             return arrangements;
//         },
//         '?' => {
//             const run_length = std.mem.indexOfAny(u8, input.line, ".#") orelse return 1;

//             if (run_length < input.nums[0]) {
//                 var nums = try std.mem.Allocator.dupe(allocator, u8, input.nums);
//                 nums[0] -= @as(u8, @intCast(run_length));
//                 try gc.append(nums);

//                 const arrangements = try getArrangements(
//                     Input{
//                         .line = input.line[run_length..],
//                         .nums = nums,
//                     },
//                     memo,
//                     gc,
//                     allocator,
//                 );
//                 try memo.put(input, arrangements);
//                 return arrangements;
//             }

//             if (run_length == input.nums[0]) {
//                 const arrangements = try getArrangements(
//                     Input{
//                         .line = input.line[run_length..],
//                         .nums = input.nums[1..],
//                     },
//                     memo,
//                     gc,
//                     allocator,
//                 );
//                 try memo.put(input, arrangements);
//                 return arrangements;
//             }

//             const l = try getArrangements(
//                 Input{
//                     .line = input.line[input.nums[0]..],
//                     .nums = input.nums[1..],
//                 },
//                 memo,
//                 gc,
//                 allocator,
//             );
//             const r = try getArrangements(
//                 Input{
//                     .line = input.line[1..],
//                     .nums = input.nums,
//                 },
//                 memo,
//                 gc,
//                 allocator,
//             );
//             try memo.put(input, l + r);
//             return l + r;
//         },
//         else => @panic("ruh roh"),
//     }
// }
