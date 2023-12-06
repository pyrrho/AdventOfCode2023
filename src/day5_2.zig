const std = @import("std");
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

// Assumptions:
// - numbers are uint32s, but ranges extend to uint64
// - order of sections is consistent:
//   - seeds
//   - seed-to-soil
//   - soil-to-fertilizer
//   - fertilizer-to-water
//   - water-to-light
//   - light-to-temperature
//   - temperature-to-humidity
//   - humidity-to-location

const MapTriple = struct {
    from: u64,
    to: u64,
    run: u64,

    pub fn sortAsc(_: void, lhs: MapTriple, rhs: MapTriple) bool {
        return lhs.from < rhs.from;
    }

    pub fn sortDesc(_: void, lhs: MapTriple, rhs: MapTriple) bool {
        return lhs.from > rhs.from;
    }
};

const Range = struct {
    start: u64,
    run: u64,

    pub fn sortAsc(_: void, lhs: Range, rhs: Range) bool {
        return lhs.start < rhs.start;
    }

    pub fn sortDesc(_: void, lhs: Range, rhs: Range) bool {
        return lhs.start > rhs.start;
    }
};

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("MEMORY LEAK");
    }

    const file = try std.fs.cwd().openFile("src/day5_input.txt", .{});
    var br = std.io.bufferedReader(file.reader());
    var in_stream = br.reader();

    var buf = ArrayList(u8).init(allocator);
    defer buf.deinit();

    var seed_ranges = ArrayList(Range).init(allocator);
    var seed_to_soil = ArrayList(MapTriple).init(allocator);
    var soil_to_fertilizer = ArrayList(MapTriple).init(allocator);
    var fertilizer_to_water = ArrayList(MapTriple).init(allocator);
    var water_to_light = ArrayList(MapTriple).init(allocator);
    var light_to_temperature = ArrayList(MapTriple).init(allocator);
    var temperature_to_humidity = ArrayList(MapTriple).init(allocator);
    var humidity_to_location = ArrayList(MapTriple).init(allocator);
    defer seed_ranges.deinit();
    defer seed_to_soil.deinit();
    defer soil_to_fertilizer.deinit();
    defer fertilizer_to_water.deinit();
    defer water_to_light.deinit();
    defer light_to_temperature.deinit();
    defer temperature_to_humidity.deinit();
    defer humidity_to_location.deinit();

    // Parsing logic
    // =========================================================================

    // Exatly: "seeds: (\d+)( \d+)*"
    try in_stream.readUntilDelimiterArrayList(&buf, '\n', 4096);
    {
        // skip "seeds: "
        const idx = std.mem.indexOf(u8, buf.items, ":").? + 2;

        var tokens = std.mem.tokenizeSequence(u8, buf.items[idx..], " ");
        while (true) {
            const start_str = tokens.next();
            const run_str = tokens.next();

            if (run_str == null) {
                break;
            }

            const start = try std.fmt.parseInt(u64, start_str.?, 10);
            const run = try std.fmt.parseInt(u64, run_str.?, 10);

            try seed_ranges.append(Range{ .start = start, .run = run });
        }
    }

    // Exactly: ""
    try in_stream.readUntilDelimiterArrayList(&buf, '\n', 4096);

    // Exactly: "seed_to_soil map:"
    try in_stream.readUntilDelimiterArrayList(&buf, '\n', 4096);
    // Repeated: \d+ \d+ \d+
    try populateMap(&seed_to_soil, in_stream, &buf);

    // Exactly: "soil_to_fertilizer map:"
    try in_stream.readUntilDelimiterArrayList(&buf, '\n', 4096);
    // Repeated: \d+ \d+ \d+
    try populateMap(&soil_to_fertilizer, in_stream, &buf);

    // Exactly: "fertilizer_to_water map:"
    try in_stream.readUntilDelimiterArrayList(&buf, '\n', 4096);
    // Repeated: \d+ \d+ \d+
    try populateMap(&fertilizer_to_water, in_stream, &buf);

    // Exactly: "water_to_light map:"
    try in_stream.readUntilDelimiterArrayList(&buf, '\n', 4096);
    // Repeated: \d+ \d+ \d+
    try populateMap(&water_to_light, in_stream, &buf);

    // Exactly: "light_to_temperature map:"
    try in_stream.readUntilDelimiterArrayList(&buf, '\n', 4096);
    // Repeated: \d+ \d+ \d+
    try populateMap(&light_to_temperature, in_stream, &buf);

    // Exactly: "temperature_to_humidity map:"
    try in_stream.readUntilDelimiterArrayList(&buf, '\n', 4096);
    // Repeated: \d+ \d+ \d+
    try populateMap(&temperature_to_humidity, in_stream, &buf);

    // Exactly: "humidity_to_location map:"
    try in_stream.readUntilDelimiterArrayList(&buf, '\n', 4096);
    // Repeated: \d+ \d+ \d+
    try populateMap(&humidity_to_location, in_stream, &buf);

    // Sort the maps base on `.from`.
    std.mem.sort(MapTriple, seed_to_soil.items, {}, MapTriple.sortAsc);
    std.mem.sort(MapTriple, soil_to_fertilizer.items, {}, MapTriple.sortAsc);
    std.mem.sort(MapTriple, fertilizer_to_water.items, {}, MapTriple.sortAsc);
    std.mem.sort(MapTriple, water_to_light.items, {}, MapTriple.sortAsc);
    std.mem.sort(MapTriple, light_to_temperature.items, {}, MapTriple.sortAsc);
    std.mem.sort(MapTriple, temperature_to_humidity.items, {}, MapTriple.sortAsc);
    std.mem.sort(MapTriple, humidity_to_location.items, {}, MapTriple.sortAsc);

    // Tracking logic
    // =========================================================================
    var lowest_loc: ?u64 = null;
    var i: usize = 0;
    while (i < seed_ranges.items.len) : (i += 1) {
        const soil_ranges = try mapFrom(seed_ranges.items[i .. i + 1], &seed_to_soil, allocator);
        const fertilizer_ranges = try mapFrom(soil_ranges.items, &soil_to_fertilizer, allocator);
        const water_ranges = try mapFrom(fertilizer_ranges.items, &fertilizer_to_water, allocator);
        const light_ranges = try mapFrom(water_ranges.items, &water_to_light, allocator);
        const temperature_ranges = try mapFrom(light_ranges.items, &light_to_temperature, allocator);
        const humidity_ranges = try mapFrom(temperature_ranges.items, &temperature_to_humidity, allocator);
        const location_ranges = try mapFrom(humidity_ranges.items, &humidity_to_location, allocator);
        defer soil_ranges.deinit();
        defer fertilizer_ranges.deinit();
        defer water_ranges.deinit();
        defer light_ranges.deinit();
        defer temperature_ranges.deinit();
        defer humidity_ranges.deinit();
        defer location_ranges.deinit();

        lowest_loc = if (lowest_loc == null)
            location_ranges.items[0].start
        else
            @min(lowest_loc.?, location_ranges.items[0].start);
    }

    try stdout.print("{?d}\n", .{lowest_loc});
}

fn populateMap(
    map: *std.ArrayList(MapTriple),
    in_stream: anytype,
    buf: *std.ArrayList(u8),
) !void {
    while (true) {
        in_stream.readUntilDelimiterArrayList(buf, '\n', 4096) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (buf.items.len == 0) {
            break;
        }

        var tokens = std.mem.tokenizeSequence(u8, buf.items, " ");
        const triple = MapTriple{
            .to = try std.fmt.parseInt(u64, tokens.next().?, 10),
            .from = try std.fmt.parseInt(u64, tokens.next().?, 10),
            .run = try std.fmt.parseInt(u64, tokens.next().?, 10),
        };
        try map.append(triple);
    }
}

fn mapFrom(
    ranges: []const Range,
    map: *ArrayList(MapTriple),
    allocator: std.mem.Allocator,
) !ArrayList(Range) {
    var ret = ArrayList(Range).init(allocator);

    for (ranges) |range_| {
        // mutable copy of the range currently being processed.
        // TODO: There's probably an easier way to gurantee the Range in the
        //       ArrayList won't be modified.
        var range = Range{
            .start = range_.start,
            .run = range_.run,
        };

        // Scan through `map` to initialize `left` s.t. `left.from <=
        // range.start` and `right` s.t. `right.from > range.start`.
        var idx: usize = 0;
        var left: ?MapTriple = null;
        var right: ?MapTriple = map.items[0];
        {
            while (idx < map.items.len) {
                if (right != null and right.?.from > range.start) {
                    break;
                }

                idx += 1;
                right = if (idx < map.items.len) map.items[idx] else null;
                left = if (idx - 1 >= 0) map.items[idx - 1] else null;
            }
        }

        // If `left` is null, it means the `range` is before the first mapping
        //element; use an identity map until we reach `right`.
        if (left == null) {
            std.debug.assert(right != null);

            const run = @min(right.?.from - range.start, range.run);
            std.debug.assert(run > 0);

            try ret.append(Range{
                .start = range.start,
                .run = run,
            });

            range.start += run;
            range.run -= run;
            if (range.run == 0) {
                break;
            }

            idx += 1;
            std.debug.assert(idx <= map.items.len);
            left = map.items[idx - 1];
            right = if (idx < map.items.len) map.items[idx] else null;
        }

        while (range.run != 0) {
            std.debug.assert(left != null);
            std.debug.assert(left.?.from <= range.start);

            // ex; 52 - 51; we're one step into the `left` range.
            const offset = range.start - left.?.from;

            // If `range` is within the `left` range, we map using `left`.
            if (offset < left.?.run) {
                const run = @min(left.?.run - offset, range.run);

                try ret.append(Range{
                    .start = left.?.to + offset,
                    .run = run,
                });

                range.start += run;
                range.run -= run;
                if (range.run == 0) {
                    break;
                }
            }

            // `range` has past the `left` range. One of three things is true;
            // - `right` is null (we're past all mapping ranges) -- we need to
            //   create an identity range for the rest of `range`.
            // - `range.start` is before `right.from` -- we need to create an
            //   identity range up until `right.from`.
            // - `range.start` is at `right.from` -- we need to advance `left`
            //   and `right` and continue.

            if (right == null) {
                try ret.append(Range{
                    .start = range.start,
                    .run = range.run,
                });

                break;
            }

            if (right.?.from > range.start) {
                const run = @min(right.?.from - range.start, range.run);
                std.debug.assert(run > 0);

                try ret.append(Range{
                    .start = range.start,
                    .run = run,
                });

                range.start += run;
                range.run -= run;
                if (range.run == 0) {
                    break;
                }
            }

            std.debug.assert(right.?.from == range.start);

            idx += 1;
            std.debug.assert(idx <= map.items.len);
            left = map.items[idx - 1];
            right = if (idx < map.items.len) map.items[idx] else null;
        }
    }

    std.mem.sort(Range, ret.items, {}, Range.sortAsc);

    // Now that we have a sorted range, we can move thorugh it to collapse
    // neighboring entries.
    var i: usize = 0;
    var last = &ret.items[i];
    for (ret.items[1..]) |range| {
        if (last.start + last.run == range.start) {
            last.run += range.run;
        } else {
            i += 1;
            last = &ret.items[i];
        }
    }

    ret.shrinkAndFree(i + 1);
    return ret;

    // var res2 = ArrayList(Range).init(allocator);
    // try res2.append(res.items[0]);

    // var last = res2.items[0];
    // for (res.items[1..]) |range| {
    //     if (last.start + last.run == range.start) {
    //         last.run += range.run;
    //     } else {
    //         try res2.append(range);
    //     }
    // }
    // return res2;
}
