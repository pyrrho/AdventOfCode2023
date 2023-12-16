const std = @import("std");
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

const SAMPLE = false;
const FILE_PATH = if (SAMPLE) "src/day15_sample_input.txt" else "src/day15_input.txt";

const Lens = struct {
    label: []const u8,
    focal_length: u16,
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

    var segments = ArrayList([]const u8).init(allocator);
    defer {
        for (segments.items) |segment| {
            allocator.free(segment);
        }
        segments.deinit();
    }

    {
        var buf = ArrayList(u8).init(allocator);
        const writer = buf.writer();
        while (true) {
            in_stream.streamUntilDelimiter(writer, ',', 1024) catch |err| switch (err) {
                error.EndOfStream => {
                    // With an EOF, we probably have a trailing newline that we don't want to track.
                    if (buf.items[buf.items.len - 1] == '\n') {
                        buf.shrinkAndFree(buf.items.len - 1);
                    }
                    try segments.append(try buf.toOwnedSlice());

                    break;
                },
                else => return err,
            };
            try segments.append(try buf.toOwnedSlice());
        }
    }

    var lens_map = AutoHashMap(u8, ArrayList(Lens)).init(allocator);
    defer {
        var itr = lens_map.valueIterator();
        while (itr.next()) |v| {
            v.deinit();
        }
        lens_map.deinit();
    }

    for (segments.items) |segment| {
        const label_end = std.mem.indexOfAny(u8, segment, ("=-")).?;
        const label = segment[0..label_end];
        const operation = segment[label_end];

        const hash = hash17(label);
        if (operation == '-') {
            if (lens_map.getPtr(hash)) |lenses| {
                var idx: ?usize = null;
                for (lenses.*.items, 0..) |lens, i| {
                    if (std.mem.eql(u8, lens.label, label)) {
                        idx = i;
                        break;
                    }
                }

                if (idx != null) {
                    _ = lenses.*.orderedRemove(idx.?);
                }
            }
        }
        if (operation == '=') {
            const focal_length = try std.fmt.parseInt(u16, segment[label_end + 1 ..], 10);
            if (lens_map.getPtr(hash)) |lenses| {
                var idx: ?usize = null;
                for (lenses.*.items, 0..) |lens, i| {
                    if (std.mem.eql(u8, lens.label, label)) {
                        idx = i;
                        break;
                    }
                }

                if (idx == null) {
                    try lenses.*.append(Lens{ .label = label, .focal_length = focal_length });
                } else {
                    lenses.*.items[idx.?].focal_length = focal_length;
                }
            } else {
                var lenses = ArrayList(Lens).init(allocator);
                try lenses.append(Lens{ .label = label, .focal_length = focal_length });
                try lens_map.put(hash, lenses);
            }
        }
    }

    var focal_power: u64 = 0;
    var itr = lens_map.iterator();
    while (itr.next()) |entry| {
        const key = entry.key_ptr.*;
        const lenses = entry.value_ptr.*.items;
        for (lenses, 1..) |lens, i| {
            focal_power += (key + 1) * i * lens.focal_length;
        }
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("focal_power: {}\n", .{focal_power});
}

fn hash17(str: []const u8) u8 {
    var h: u64 = 0;
    for (str) |c| {
        h += c;
        h *= 17;
        h %= 256;
    }
    return @as(u8, @intCast(h));
}

// if :
// The current value starts at 0.
// The first character is H; its ASCII code is 72.
// The current value increases to 72.
// The current value is multiplied by 17 to become 1224.
// The current value becomes 200 (the remainder of 1224 divided by 256).
// The next character is A; its ASCII code is 65.
// The current value increases to 265.
// The current value is multiplied by 17 to become 4505.
// The current value becomes 153 (the remainder of 4505 divided by 256).
// The next character is S; its ASCII code is 83.
// The current value increases to 236.
// The current value is multiplied by 17 to become 4012.
// The current value becomes 172 (the remainder of 4012 divided by 256).
// The next character is H; its ASCII code is 72.
// The current value increases to 244.
// The current value is multiplied by 17 to become 4148.
// The current value becomes 52 (the remainder of 4148 divided by 256).
