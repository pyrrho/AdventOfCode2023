const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;
const StringHashMap = std.StringHashMap;

const SAMPLE = false;
const FILE_PATH = if (SAMPLE) "src/day19_sample_input.txt" else "src/day19_input.txt";

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

    var flows = StringHashMap(Flow).init(allocator);
    defer {
        var itr = flows.valueIterator();
        while (itr.next()) |flow| {
            for (flow.checks) |check| {
                switch (check.action) {
                    .next_flow => |f| allocator.free(f),
                    else => {},
                }
            }
            allocator.free(flow.checks);
            allocator.free(flow.name);
        }
        flows.deinit();
    }

    var parts = ArrayList(Part).init(allocator);
    defer parts.deinit();

    {
        var buf = ArrayList(u8).init(allocator);
        defer buf.deinit();
        const writer = buf.writer();

        // First loop to parse Flows.
        while (true) {
            in_stream.streamUntilDelimiter(writer, '\n', null) catch |err| switch (err) {
                error.EndOfStream => @panic("Not supposed to hit EoF yet."),
                else => {
                    buf.deinit();
                    return err;
                },
            };

            // A blank line indicates we need to switch to parsing parts
            if (buf.items.len == 0) break;

            const name_len = std.mem.indexOf(u8, buf.items, "{").?;
            const name = try allocator.alloc(u8, name_len);
            @memcpy(name, buf.items[0..name_len]);

            // We don't want to include the '{' or '}' when parsing the checks
            const checks_start = name_len + 1;
            const checks_end = buf.items.len - 1;

            const checks = try parseChecks(buf.items[checks_start..checks_end], allocator);

            try flows.put(name, Flow{
                .name = name,
                .checks = checks,
            });

            buf.clearRetainingCapacity();
        }

        // Second loop to parse Parts.
        while (true) {
            in_stream.streamUntilDelimiter(writer, '\n', null) catch |err| switch (err) {
                error.EndOfStream => break,
                else => {
                    buf.deinit();
                    return err;
                },
            };

            // Allocate an array of four u32s to track category values. The array should be indexed
            // with `@intFromEnum(Category.*)` to get or set the value for the given category.
            // NB. This is Extra. But I want my parsing routine to be robust respective to order
            //     because it's late and I'm tired and shut up I won't do what you tell me. :p
            var categories: [4]u32 = undefined;

            var category_strings = std.mem.tokenizeSequence(u8, buf.items[1 .. buf.items.len - 1], ",");
            while (category_strings.next()) |cat_str| {
                const cat = Category.fromChar(cat_str[0]);
                const val = try std.fmt.parseInt(u32, cat_str[2..], 10);
                categories[@intFromEnum(cat)] = val;
            }

            try parts.append(Part{
                .x = categories[@intFromEnum(Category.x)],
                .m = categories[@intFromEnum(Category.m)],
                .a = categories[@intFromEnum(Category.a)],
                .s = categories[@intFromEnum(Category.s)],
            });

            buf.clearRetainingCapacity();
        }
    }

    // Print stuff for great debugging
    if (false) {
        for (parts.items) |part| {
            std.debug.print(
                "Part {{x: {d: >4}, m: {d: >4}, a: {d: >4}, s: {d: >4}}}\n",
                .{ part.x, part.m, part.a, part.s },
            );
        }
        std.debug.print("\n", .{});

        var itr = flows.valueIterator();
        while (itr.next()) |flow| {
            std.debug.print("Flow {{name: {s}, checks: [\n", .{flow.*.name});
            for (flow.*.checks) |check| {
                switch (check.action) {
                    .next_flow => |f| std.debug.print("  {s} {s} {d} : Start Flow '{s}',\n", .{
                        @tagName(check.category),
                        @tagName(check.operation),
                        check.value,
                        f,
                    }),
                    else => std.debug.print("  {s} {s} {d} : {s},\n", .{
                        @tagName(check.category),
                        @tagName(check.operation),
                        check.value,
                        @tagName(check.action),
                    }),
                }
            }
            std.debug.print("]}}\n", .{});
        }
    }

    // Push parts through the flows.
    const in_flow = flows.get("in").?;
    var sum: u64 = 0;

    partloop: for (parts.items) |part| {
        var checks = in_flow.checks;
        var check_idx: usize = 0;
        checkloop: while (true) {
            const check = checks[check_idx];

            switch (check.operation) {
                .noop => {},
                .gt => if (part.get(check.category) <= check.value) {
                    check_idx += 1;
                    continue :checkloop;
                },
                .lt => if (part.get(check.category) >= check.value) {
                    check_idx += 1;
                    continue :checkloop;
                },
            }

            switch (check.action) {
                .accept => {
                    sum += part.x;
                    sum += part.m;
                    sum += part.a;
                    sum += part.s;
                    continue :partloop;
                },
                .reject => continue :partloop,
                .next_flow => {
                    checks = flows.get(check.action.next_flow).?.checks;
                    check_idx = 0;
                    continue;
                },
            }
        }
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Sum: {d}\n", .{sum});
}

fn parseChecks(buf: []const u8, allocator: Allocator) ![]Check {
    var checks = ArrayList(Check).init(allocator);
    var tokens = std.mem.tokenizeSequence(u8, buf, ",");

    while (tokens.next()) |t| {
        const sep_idx = std.mem.indexOf(u8, t, ":");

        if (sep_idx == null) {
            // We a noop check that's just an Action
            try checks.append(Check{
                .category = .x,
                .operation = .noop,
                .value = 0,
                .action = try parseAction(t, allocator),
            });

            continue;
        }

        const category = Category.fromChar(t[0]);
        const operation = Operation.fromChar(t[1]);
        const value = try std.fmt.parseInt(u32, t[2..sep_idx.?], 10);
        const action = try parseAction(t[sep_idx.? + 1 .. t.len], allocator);

        try checks.append(Check{
            .category = category,
            .operation = operation,
            .value = value,
            .action = action,
        });
    }

    return checks.toOwnedSlice();
}

fn parseAction(s: []const u8, allocator: Allocator) !Action {
    if (s.len == 1) {
        if (s[0] == 'A') return .accept;
        if (s[0] == 'R') return .reject;
    }
    const flow = try allocator.alloc(u8, s.len);
    @memcpy(flow, s);
    return .{ .next_flow = flow };
}

// Types
// =============================================================================

const Part = struct {
    x: u32,
    m: u32,
    a: u32,
    s: u32,

    pub fn get(self: Part, cat: Category) u32 {
        return switch (cat) {
            .x => self.x,
            .m => self.m,
            .a => self.a,
            .s => self.s,
        };
    }
};

const Flow = struct {
    name: []const u8,
    checks: []Check,
};

const Check = struct {
    category: Category,
    operation: Operation,
    value: u32,
    action: Action,
};

const Category = enum(usize) {
    x,
    m,
    a,
    s,

    pub fn fromChar(c: u8) Category {
        return switch (c) {
            'x' => .x,
            'm' => .m,
            'a' => .a,
            's' => .s,
            else => @panic("Invalid category character"),
        };
    }
};

const Operation = enum {
    gt,
    lt,
    noop,

    pub fn fromChar(c: u8) Operation {
        return switch (c) {
            '>' => .gt,
            '<' => .lt,
            else => @panic("Invalid operation character"),
        };
    }
};

const Action = union(enum) {
    accept,
    reject,
    next_flow: []const u8,
};
