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
    }

    // Print stuff for great debugging
    if (false) {
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

    // Build a list of accepting flows
    const in_flow = flows.get("in").?;
    var sum: u64 = 0;

    var accepting_flows = ArrayList([]Check).init(allocator);
    var accepted_checks = ArrayList(Check).init(allocator);
    defer {
        for (accepting_flows.items) |checks| allocator.free(checks);
        accepting_flows.deinit();
    }

    extractAccepting(
        in_flow.checks,
        flows,
        &accepted_checks,
        &accepting_flows,
    ) catch |err| {
        // Only free accepted_checks if this method fails; otherwise it -- and
        // all clones of it -- will have been `deinit()`d by a .reject action,
        // or `.toOwnedSlice()`d and added to `accepting_flows` in an .accept
        // action.
        accepted_checks.deinit();
        return err;
    };

    // Print stuff for great debugging
    if (false) {
        std.debug.print("Accepting Flows: [\n", .{});
        for (accepting_flows.items) |flow| {
            for (flow) |check| {
                switch (check.action) {
                    .next_flow => |f| std.debug.print("    {s} {s} {d} : Start Flow '{s}',\n", .{
                        @tagName(check.category),
                        @tagName(check.operation),
                        check.value,
                        f,
                    }),
                    else => std.debug.print("    {s} {s} {d} : {s},\n", .{
                        @tagName(check.category),
                        @tagName(check.operation),
                        check.value,
                        @tagName(check.action),
                    }),
                }
            }
            std.debug.print("  ],\n", .{});
        }
    }

    // Map accepting flows to their part range
    for (accepting_flows.items) |flow| {
        var part_range = PartRange{};
        for (flow) |check| {
            part_range.boundToCheck(check);
        }

        sum +=
            (part_range.x[1] - part_range.x[0] + 1) *
            (part_range.m[1] - part_range.m[0] + 1) *
            (part_range.a[1] - part_range.a[0] + 1) *
            (part_range.s[1] - part_range.s[0] + 1);
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

fn extractAccepting(
    pending_checks: []Check,
    flows: StringHashMap(Flow),
    accepted_checks: *ArrayList(Check),
    resolved_flows: *ArrayList([]Check),
) !void {
    const check = pending_checks[0];
    const remaining_checks = pending_checks[1..];
    switch (check.operation) {
        .noop => {
            switch (check.action) {
                .reject => {
                    accepted_checks.deinit();
                    return;
                },
                .accept => {
                    try accepted_checks.append(check);
                    try resolved_flows.append(try accepted_checks.toOwnedSlice());
                    return;
                },
                .next_flow => {
                    try accepted_checks.append(check);
                    const next_flow = flows.get(check.action.next_flow).?;
                    try extractAccepting(
                        next_flow.checks,
                        flows,
                        accepted_checks,
                        resolved_flows,
                    );
                },
                .pass => @panic("'.pass' is not a valid action to parse"),
            }
        },
        .gt, .lt => {
            var left = try accepted_checks.clone();
            try left.append(.{
                .category = check.category,
                .operation = check.operation.opposite(),
                .value = check.value,
                .action = Action.pass,
            });
            try extractAccepting(
                remaining_checks,
                flows,
                &left,
                resolved_flows,
            );

            var right = accepted_checks;
            switch (check.action) {
                .reject => {
                    right.deinit();
                    return;
                },
                .accept => {
                    try right.append(check);
                    try resolved_flows.append(try right.toOwnedSlice());
                    return;
                },
                .next_flow => {
                    try right.append(check);
                    const next_flow = flows.get(check.action.next_flow).?;
                    try extractAccepting(
                        next_flow.checks,
                        flows,
                        right,
                        resolved_flows,
                    );
                },
                .pass => @panic("'.pass' is not a valid action to parse"),
            }
        },
        else => @panic("Invalid operation"),
    }
}

// Types
// =============================================================================

const PartRange = struct {
    x: [2]u64 = .{ 1, 4000 },
    m: [2]u64 = .{ 1, 4000 },
    a: [2]u64 = .{ 1, 4000 },
    s: [2]u64 = .{ 1, 4000 },

    pub fn boundToCheck(self: *PartRange, check: Check) void {
        switch (check.operation) {
            .noop => {},
            .gt => {
                switch (check.category) {
                    .x => self.x[0] = check.value + 1,
                    .m => self.m[0] = check.value + 1,
                    .a => self.a[0] = check.value + 1,
                    .s => self.s[0] = check.value + 1,
                }
            },
            .lt => {
                switch (check.category) {
                    .x => self.x[1] = check.value - 1,
                    .m => self.m[1] = check.value - 1,
                    .a => self.a[1] = check.value - 1,
                    .s => self.s[1] = check.value - 1,
                }
            },
            .geq => {
                switch (check.category) {
                    .x => self.x[0] = check.value,
                    .m => self.m[0] = check.value,
                    .a => self.a[0] = check.value,
                    .s => self.s[0] = check.value,
                }
            },
            .leq => {
                switch (check.category) {
                    .x => self.x[1] = check.value,
                    .m => self.m[1] = check.value,
                    .a => self.a[1] = check.value,
                    .s => self.s[1] = check.value,
                }
            },
        }
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
    geq,
    leq,
    noop,

    pub fn fromChar(c: u8) Operation {
        return switch (c) {
            '>' => .gt,
            '<' => .lt,
            else => @panic("Invalid operation character"),
        };
    }

    pub fn opposite(self: Operation) Operation {
        return switch (self) {
            .gt => .leq,
            .lt => .geq,
            else => @panic("No opposite operation"),
        };
    }
};

const Action = union(enum) {
    pass,
    next_flow: []const u8,
    accept,
    reject,
};
