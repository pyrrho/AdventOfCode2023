const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const file = try std.fs.cwd().openFile("src/day6_input.txt", .{});
    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("MEMORY LEAK");
    }

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    var times = std.ArrayList(u64).init(allocator);
    var distances = std.ArrayList(u64).init(allocator);
    defer times.deinit();
    defer distances.deinit();

    // Parse times
    try in_stream.readUntilDelimiterArrayList(&buf, '\n', 4096);
    {
        // Skip "Time:"
        var tokens = std.mem.tokenizeSequence(u8, buf.items[5..], " ");
        while (tokens.next()) |token| {
            try times.append(try std.fmt.parseInt(u64, token, 10));
        }
    }
    // Parse distances.
    try in_stream.readUntilDelimiterArrayList(&buf, '\n', 4096);
    {
        // Skip "Distance:"
        var tokens = std.mem.tokenizeSequence(u8, buf.items[9..], " ");
        while (tokens.next()) |token| {
            try distances.append(try std.fmt.parseInt(u64, token, 10));
        }
    }

    std.debug.assert(times.items.len == distances.items.len);

    var margin_of_error: ?u64 = null;
    var i: usize = 0;
    while (i < times.items.len) : (i += 1) {
        const time = times.items[i];
        const dist = distances.items[i];

        const a: f64 = -1.0;
        const b: f64 = @as(f64, @floatFromInt(time));
        const c: f64 = -@as(f64, (@floatFromInt(dist)));

        const xa: f64 = (-b + std.math.sqrt((b * b) - (4.0 * a * c))) / (2.0 * a);
        const xb: f64 = (-b - std.math.sqrt((b * b) - (4.0 * a * c))) / (2.0 * a);

        const xaf = @as(u64, @intFromFloat(std.math.floor(xa)));
        const xbc = @as(u64, @intFromFloat(std.math.ceil(xb)));

        const winning_count = xbc - xaf - 1;

        margin_of_error = if (margin_of_error == null)
            winning_count
        else
            margin_of_error.? * winning_count;
    }

    try stdout.print("Margin of error: {?d}\n", .{margin_of_error});
}
