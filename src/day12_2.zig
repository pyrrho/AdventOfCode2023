const std = @import("std");
const ArrayList = std.ArrayList;

const Input = struct {
    line: []const u8,
    current_run: u8,
    runs: []const u8,
};

// Hash context for Input.
pub const InputContext = struct {
    pub fn hash(self: @This(), s: Input) u64 {
        _ = self;
        // FIXME: This is so wrong. The u64 keyspace is pretty large, so there's
        //        a reasonable chance we won't see any colisions, but there's a
        //        _lot_ of lost entorpy in these wrapping additions. This really
        //        should instantiate a `std.hash.Wyhash`, and `.update` each
        //        field into the stateful hasher.
        return std.hash.Wyhash.hash(0, s.line) +%
            std.hash.Wyhash.hash(0, s.runs) +%
            std.hash.Wyhash.hash(0, std.mem.asBytes(&s.current_run));
    }
    pub fn eql(self: @This(), a: Input, b: Input) bool {
        _ = self;
        return a.current_run == b.current_run and
            std.mem.eql(u8, a.line, b.line) and
            std.mem.eql(u8, a.runs, b.runs);
    }
};
const InputMemo = std.HashMap(Input, u64, InputContext, std.hash_map.default_max_load_percentage);

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
        const l = tokens.next().?;

        const line = try allocator.alloc(u8, (l.len * 5) + 4);
        @memcpy(line[0..l.len], l);
        for (1..5) |i| {
            const e = (i * l.len) + i;
            line[e - 1] = '?';
            @memcpy(line[e .. e + l.len], l);
        }

        var runs = ArrayList(u8).init(allocator);
        var num_tokens = std.mem.tokenizeSequence(u8, tokens.next().?, ",");
        while (num_tokens.next()) |token| {
            const num = try std.fmt.parseInt(u8, token, 10);
            try runs.append(num);
        }
        const initial_len = runs.items.len;
        try runs.ensureUnusedCapacity(runs.items.len * 4);
        for (0..4) |_| try runs.appendSlice(runs.items[0..initial_len]);

        try input.append(Input{
            .line = line,
            .current_run = 0,
            .runs = try runs.toOwnedSlice(),
        });
    }

    var memo = InputMemo.init(allocator);
    defer memo.deinit();

    const stdout = std.io.getStdOut().writer();

    var arrangements: u64 = 0;
    for (input.items) |e| {
        arrangements += try getArrangements(e, &memo);
    }

    try stdout.print("Arrangements: {}\n", .{arrangements});
}

fn getArrangements(
    input: Input,
    memo: *InputMemo,
) !u64 {
    if (memo.get(input)) |arrangements| {
        return arrangements;
    }

    var i: usize = 0;
    var r_i: usize = 0;
    var current_run: u8 = input.current_run;
    while (true) {
        const at_last_run = r_i == input.runs.len;
        const last_run_done = at_last_run and current_run == 0;

        // If we're at the end of the line, and have no more runs to fill, we've
        // found a valid arrangement. Otherwise, we've found an invalid one.
        if (i == input.line.len) {
            return if (last_run_done) 1 else 0;
        }

        const c = input.line[i];

        switch (c) {
            '.' => {
                // If we aren't at the end of a run, seeing a '.' means this is
                // an invalid arrangement.
                if (current_run != 0) {
                    return 0;
                }

                const run_len = (std.mem.indexOfAnyPos(u8, input.line, i, "#?") orelse input.line.len) - i;
                i += run_len;

                continue;
            },
            '#' => {
                // If we're at the end of the previous run, it's time to start
                // the next one.
                if (current_run == 0) {
                    // If there isn't a next one, this is an invalid arrangement.
                    if (r_i == input.runs.len) {
                        return 0;
                    }
                    current_run = input.runs[r_i];
                    r_i += 1;
                }

                const run_len = (std.mem.indexOfAnyPos(u8, input.line, i, ".?") orelse input.line.len) - i;
                // If the number of sequential '#'s is larger than the run we're
                // in, it's and invalid arrangement.
                if (run_len > current_run) {
                    return 0;
                }

                current_run -= @as(u8, @intCast(run_len));
                i += run_len;

                // If we just finished a run, and the next char is a '?', it
                // must be a '.'. So skip it.
                if (current_run == 0 and i < input.line.len and input.line[i] == '?') {
                    i += 1;
                }

                continue;
            },
            '?' => {
                const run_len = (std.mem.indexOfAnyPos(u8, input.line, i, ".#") orelse input.line.len) - i;

                // If we're in the middle of a run, we have no choice but to continue it.
                if (current_run != 0) {
                    const steps = @min(current_run, run_len);
                    current_run -= steps;
                    i += steps;

                    // If this finishes the run, either the next char is:
                    // - Past the end of `input.line`, which means the sequence
                    //   is finished. We can continue as normal and terminate at
                    //   the top of the loop.
                    // - A '.', which is a valid sequenece.
                    // - A '#', which is an invalid sequence.
                    // - A '?' that needs to be converted into a '.'. So we skip
                    //   over it, and continue.
                    if (current_run == 0 and i < input.line.len) {
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

                // Otherwise, we can either insert a single '.', skipping over
                // the next char, and coninuing ...
                const inserting_dot = try getArrangements(
                    Input{
                        .line = input.line[i + 1 ..],
                        .current_run = 0,
                        .runs = input.runs[r_i..],
                    },
                    memo,
                );

                // ... or by choosing to read the next '?' as a '#' by starting
                // the next run, and re-entering the loop to ensure we count the
                // pending '?' as a '#'.
                const inserting_hash = try getArrangements(
                    Input{
                        .line = input.line[i..],
                        .current_run = input.runs[r_i],
                        .runs = input.runs[r_i + 1 ..],
                    },
                    memo,
                );

                // Aggregate and return.
                const arrangements = inserting_dot + inserting_hash;
                try memo.put(input, arrangements);
                return arrangements;
            },
            else => @panic("Invalid input character"),
        }
    }
}
