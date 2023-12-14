const std = @import("std");
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

// const file_path = "src/day14_sample_input.txt";
// const Z: usize = 10;
const file_path = "src/day14_input.txt";
const Z: usize = 100;

const Field = [Z][Z]u8;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("MEMORY LEAK");
    }

    const file = try std.fs.cwd().openFile(file_path, .{});
    var buf_reader = std.io.bufferedReader(file.reader());
    const in_stream = buf_reader.reader();

    var buf = ArrayList(u8).init(allocator);
    defer buf.deinit();

    var lines: Field = undefined; //.{.{0} ** Z} ** Z;

    var i: usize = 0;
    while (true) : (i += 1) {
        in_stream.readUntilDelimiterArrayList(&buf, '\n', 1024) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        @memcpy(&lines[i], buf.items);
    }

    var seen_fields = ArrayList(*Field).init(allocator);
    var seen_map = AutoHashMap(Field, u64).init(allocator);
    defer {
        seen_map.deinit();
        for (seen_fields.items) |field| {
            allocator.free(field);
        }
        seen_fields.deinit();
    }

    var iteration: u64 = 0;
    var cycle_start: u64 = undefined;

    while (iteration < 1000000000) {
        const k = try allocator.create(Field);
        @memcpy(k, &lines);

        try seen_fields.append(k);
        try seen_map.put(k.*, iteration);

        PushNorth(&lines);
        PushWest(&lines);
        PushSouth(&lines);
        PushEast(&lines);

        iteration += 1;

        if (seen_map.get(lines)) |v| {
            cycle_start = v;
            break;
        }
    }

    std.debug.print("Cycle start: {}\n", .{cycle_start});
    std.debug.print("Iteration: {}\n", .{iteration});
    const cycle_length = iteration - cycle_start;
    const final_cycle_step = (1000000000 - iteration) % cycle_length;
    const final_field = seen_fields.items[cycle_start + final_cycle_step].*;

    var northern_load: u64 = 0;
    var x: usize = 0;
    while (x < Z) : (x += 1) {
        var y: usize = 0;

        while (y < Z) : (y += 1) {
            switch (final_field[y][x]) {
                '.' => {},
                '#' => {},
                'O' => {
                    northern_load += Z - y;
                },
                else => @panic("Invalid input"),
            }
        }
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Northern load: {}\n", .{northern_load});
}

fn PushNorth(lines: *[Z][Z]u8) void {
    var x: usize = 0;
    while (x < Z) : (x += 1) {
        var y: usize = 0;
        var next_open: usize = 0;

        while (y < Z) : (y += 1) {
            switch (lines[y][x]) {
                '.' => {},
                '#' => {
                    next_open = y + 1;
                },
                'O' => {
                    lines[y][x] = '.';
                    lines[next_open][x] = 'O';
                    next_open += 1;
                },
                else => @panic("Invalid input"),
            }
        }
    }
}

fn PushSouth(lines: *[Z][Z]u8) void {
    var x: usize = 0;
    while (x < Z) : (x += 1) {
        var y: usize = Z - 1;
        var next_open: usize = Z - 1;

        while (true) : (y -= 1) {
            switch (lines[y][x]) {
                '.' => {},
                '#' => {
                    next_open = y -% 1;
                },
                'O' => {
                    lines[y][x] = '.';
                    lines[next_open][x] = 'O';
                    next_open -%= 1;
                },
                else => @panic("Invalid input"),
            }

            if (y == 0) break;
        }
    }
}

fn PushWest(lines: *[Z][Z]u8) void {
    var y: usize = 0;
    while (y < Z) : (y += 1) {
        var x: usize = 0;
        var next_open: usize = 0;

        while (x < Z) : (x += 1) {
            switch (lines[y][x]) {
                '.' => {},
                '#' => {
                    next_open = x + 1;
                },
                'O' => {
                    lines[y][x] = '.';
                    lines[y][next_open] = 'O';
                    next_open += 1;
                },
                else => @panic("Invalid input"),
            }
        }
    }
}

fn PushEast(lines: *[Z][Z]u8) void {
    var y: usize = 0;
    while (y < Z) : (y += 1) {
        var x: usize = Z - 1;
        var next_open: usize = Z - 1;

        while (true) : (x -= 1) {
            switch (lines[y][x]) {
                '.' => {},
                '#' => {
                    next_open = x -% 1;
                },
                'O' => {
                    lines[y][x] = '.';
                    lines[y][next_open] = 'O';
                    next_open -%= 1;
                },
                else => @panic("Invalid input"),
            }

            if (x == 0) break;
        }
    }
}
