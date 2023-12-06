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
    range: u64,

    pub fn sortAsc(_: void, lhs: MapTriple, rhs: MapTriple) bool {
        return lhs.from < rhs.from;
    }

    pub fn sortDesc(_: void, lhs: MapTriple, rhs: MapTriple) bool {
        return lhs.from > rhs.from;
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

    var seeds = ArrayList(u64).init(allocator);
    var seed_to_soil = ArrayList(MapTriple).init(allocator);
    var soil_to_fertilizer = ArrayList(MapTriple).init(allocator);
    var fertilizer_to_water = ArrayList(MapTriple).init(allocator);
    var water_to_light = ArrayList(MapTriple).init(allocator);
    var light_to_temperature = ArrayList(MapTriple).init(allocator);
    var temperature_to_humidity = ArrayList(MapTriple).init(allocator);
    var humidity_to_location = ArrayList(MapTriple).init(allocator);
    defer seeds.deinit();
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
        while (tokens.next()) |token| {
            try seeds.append(try std.fmt.parseInt(u64, token, 10));
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
    std.mem.sort(MapTriple, seed_to_soil.items, {}, MapTriple.sortDesc);
    std.mem.sort(MapTriple, soil_to_fertilizer.items, {}, MapTriple.sortDesc);
    std.mem.sort(MapTriple, fertilizer_to_water.items, {}, MapTriple.sortDesc);
    std.mem.sort(MapTriple, water_to_light.items, {}, MapTriple.sortDesc);
    std.mem.sort(MapTriple, light_to_temperature.items, {}, MapTriple.sortDesc);
    std.mem.sort(MapTriple, temperature_to_humidity.items, {}, MapTriple.sortDesc);
    std.mem.sort(MapTriple, humidity_to_location.items, {}, MapTriple.sortDesc);

    // Tracking logic
    // =========================================================================
    var lowestLoc: ?u64 = null;

    for (seeds.items) |seed| {
        const soil = mapFrom(seed, &seed_to_soil);
        const fertilizer = mapFrom(soil, &soil_to_fertilizer);
        const water = mapFrom(fertilizer, &fertilizer_to_water);
        const light = mapFrom(water, &water_to_light);
        const temperature = mapFrom(light, &light_to_temperature);
        const humidity = mapFrom(temperature, &temperature_to_humidity);
        const location = mapFrom(humidity, &humidity_to_location);

        if (lowestLoc == null or location < lowestLoc.?) {
            lowestLoc = location;
        }
    }

    try stdout.print("{?d}\n", .{lowestLoc});
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
            .range = try std.fmt.parseInt(u64, tokens.next().?, 10),
        };
        try map.append(triple);
    }
}

fn mapFrom(from: u64, map: *ArrayList(MapTriple)) u64 {
    for (map.items) |triple| {
        if (triple.from <= from) {
            const delta = from - triple.from;
            if (delta <= triple.range) {
                return triple.to + delta;
            } else {
                break;
            }
        }
    }
    return from;
}
