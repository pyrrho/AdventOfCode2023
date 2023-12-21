const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;
const StringHashMap = std.StringHashMap;

const TARGET = INPUT.PRIMARY;
const INPUT = enum {
    SAMPLE_1,
    SAMPLE_2,
    PRIMARY,
};
const FILE_PATH = switch (TARGET) {
    INPUT.SAMPLE_1 => "src/day20_sample_input_1.txt",
    INPUT.SAMPLE_2 => "src/day20_sample_input_2.txt",
    INPUT.PRIMARY => "src/day20_input.txt",
};
const EXPECTED_RESULT = switch (TARGET) {
    INPUT.SAMPLE_1 => .{ 8000, 4000 },
    INPUT.SAMPLE_2 => .{ 4250, 2750 },
    INPUT.PRIMARY => .{ 0, 0 },
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

    var broadcaster_module: *Module = undefined;

    var modules: []Module = undefined;
    var module_map = AutoHashMap(Module.Id, *Module).init(allocator);

    var secondary_modules = ArrayList(Module).init(allocator);
    defer secondary_modules.deinit();

    // Parse the input file and build the Module graph.
    // =============================================================================
    {
        var buf = ArrayList(u8).init(allocator);
        defer buf.deinit();
        const writer = buf.writer();

        // For the first loop, we're going to partially initialize Module objects. The `modules`
        // list will own memory for all Modules. The `module_output_strings` list will be ordered
        // identically to the `modules` list, and will temporarily retain a copy of the ouput
        // identifier lists for each module.
        var modules_builder = ArrayList(Module).init(allocator);
        // `modules_builder` will be `.toOwnedSlice()`d.
        var moudule_output_strings = ArrayList([]const u8).init(allocator);
        defer {
            for (moudule_output_strings.items) |s| {
                allocator.free(s);
            }
            moudule_output_strings.deinit();
        }
        while (true) {
            in_stream.streamUntilDelimiter(writer, '\n', null) catch |err| switch (err) {
                error.EndOfStream => break,
                else => {
                    buf.deinit();
                    return err;
                },
            };

            var module_tokens = std.mem.tokenizeSequence(u8, buf.items, " -> ");
            const module_id_string = module_tokens.next().?;
            // NB. this is a wasted allocation in the case of the 'broadcaster' module. I'll take
            //     that hit for readability, though.
            const module_id = .{ module_id_string[1], module_id_string[2] };

            try modules_builder.append(switch (module_id_string[0]) {
                '%' => Module{
                    .id = module_id,
                    .class = .{ .flip_flop = .{} },
                },
                '&' => Module{
                    .id = module_id,
                    .class = .{ .conjunction = .{
                        .inputs = ArrayList(Module.ConjunctionInput).init(allocator),
                    } },
                },
                'b' => Module{
                    .id = "--".*,
                    .class = .broadcaster,
                },
                else => @panic("Invalid module type"),
            });

            try moudule_output_strings.append(try allocator.dupe(u8, module_tokens.next().?));

            buf.clearRetainingCapacity();
        }

        modules = try modules_builder.toOwnedSlice();

        for (modules) |*module| {
            try module_map.put(module.*.id, module);
            if (module.class == .broadcaster) {
                broadcaster_module = module;
            }
        }

        for (modules, moudule_output_strings.items) |*module, output| {
            var output_builder = ArrayList(*Module).init(allocator);

            var output_tokens = std.mem.tokenizeSequence(u8, output, ", ");
            while (output_tokens.next()) |output_id_str| {
                const output_id = .{ output_id_str[0], output_id_str[1] };
                const output_module = module_map.get(output_id);

                if (output_module != null) {
                    try output_builder.append(output_module.?);
                } else {
                    try secondary_modules.append(.{
                        .id = output_id,
                        .class = .broadcaster,
                    });
                    try output_builder.append(&secondary_modules.items[secondary_modules.items.len - 1]);
                }

                if (output_module != null and output_module.?.class == .conjunction) {
                    try output_module.?.class.conjunction.inputs.append(.{
                        .id = module.id,
                        .signal = .low,
                    });
                }
            }

            module.outputs = try output_builder.toOwnedSlice();
        }
    }

    defer {
        for (modules) |m| {
            if (m.class == .conjunction) {
                m.class.conjunction.inputs.deinit();
            }
            allocator.free(m.outputs);
        }
        allocator.free(modules);
        module_map.deinit();
    }

    // Press the button 1000 times
    // =============================================================================
    // But actually don't. Button presses can be memoized since (it's likely that?) the state
    // transitions of the module graph are cyclic. So, we can just press the button until we
    // reach a cycle, and then do some math to figure out how many signals will be sent after 1000
    // button presses.
    const module_state_generator = ModuleStateGenerator.init(&modules, allocator);
    var module_state_output = ArrayList(struct {
        low_signals: u64,
        high_signals: u64,
    }).init(allocator);
    defer module_state_output.deinit();

    var module_state_indexes = std.HashMap(
        []bool,
        usize,
        ModuleStateContext,
        std.hash_map.default_max_load_percentage,
    ).init(allocator);
    defer {
        var itr = module_state_indexes.keyIterator();
        while (itr.next()) |key| {
            allocator.free(key.*);
        }
        module_state_indexes.deinit();
    }

    var pending_sends = RingQueue(PendingSend).init(allocator);
    defer pending_sends.deinit();

    var total_low_signals: u64 = 1000; // because we count the button presses that aren't mapped in my graph.
    var total_high_signals: u64 = 0;

    var button_presses: u64 = 0;
    var cycle_start: usize = 0;
    while (button_presses < 1000) : (button_presses += 1) {
        const state = try module_state_generator.captureState();

        if (module_state_indexes.get(state)) |idx| {
            allocator.free(state);
            cycle_start = idx;
            break;
        }

        pending_sends.clearRetainingCapacity();
        try pending_sends.push(.{
            .target = broadcaster_module,
            .sender = undefined,
            .signal = Signal.low,
        });

        var low_signals: u64 = 0;
        var high_signals: u64 = 0;
        while (pending_sends.pop()) |pending| {
            const signals = try pending.target.send(
                pending.sender,
                pending.signal,
                &pending_sends,
            );
            low_signals += signals[0];
            high_signals += signals[1];
        }

        try module_state_indexes.put(state, module_state_output.items.len);
        try module_state_output.append(.{
            .low_signals = low_signals,
            .high_signals = high_signals,
        });

        total_low_signals += low_signals;
        total_high_signals += high_signals;
    }

    const cycle_len = module_state_output.items.len - cycle_start;
    const cycle_signals = blk: {
        var low_signals: u64 = 0;
        var high_signals: u64 = 0;
        for (module_state_output.items[cycle_start..]) |output| {
            low_signals += output.low_signals;
            high_signals += output.high_signals;
        }
        break :blk .{ low_signals, high_signals };
    };
    const full_cycles = @divFloor(1000 - button_presses, cycle_len);
    const remaining_cycles = (1000 - button_presses) % cycle_len;

    std.debug.print("Cycle start: {}\n", .{cycle_start});
    std.debug.print("Remaining cycles: {}\n", .{remaining_cycles});

    total_low_signals += full_cycles * cycle_signals[0];
    total_high_signals += full_cycles * cycle_signals[1];

    for (module_state_output.items[cycle_start .. cycle_start + remaining_cycles]) |output| {
        total_low_signals += output.low_signals;
        total_high_signals += output.high_signals;
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Total low signals: {}\n", .{total_low_signals});
    try stdout.print("Total high signals: {}\n", .{total_high_signals});
    try stdout.print("Expected result: {d} ({d} * {d})\n", .{
        EXPECTED_RESULT[0] * EXPECTED_RESULT[1],
        EXPECTED_RESULT[0],
        EXPECTED_RESULT[1],
    });
    try stdout.print("Actual result:   {d}\n", .{total_high_signals * total_low_signals});
}

// Types
// =============================================================================

const Signal = enum {
    low,
    high,
};

const Module = struct {
    const Self = @This();

    id: Id,
    outputs: []*Module = undefined,
    class: union(enum) {
        flip_flop: struct {
            state: State = .off,
        },
        conjunction: struct {
            inputs: ArrayList(ConjunctionInput),
        },
        broadcaster,
    },

    const Id = [2]u8;

    const State = enum {
        off,
        on,
    };

    const ConjunctionInput = struct {
        // TODO: See if we can replace this Id w/ a pointer?
        //       If that works, we might be able to rm the module.Id field and
        //       only care about ids for the map.
        id: Module.Id,
        signal: Signal,
    };

    pub fn send(
        self: *Self,
        sender: *Self,
        signal: Signal,
        pending_sends: *RingQueue(PendingSend),
    ) ![2]u64 {
        // if (std.mem.eql(u8, &self.id, "rx")) {
        //     std.debug.print("HI!!! Signal is {s}\n\n", .{@tagName(signal)});
        // }
        switch (self.class) {
            .broadcaster => {
                for (self.outputs) |output| {
                    try pending_sends.push(.{
                        .sender = self,
                        .target = output,
                        .signal = signal,
                    });
                }
                return switch (signal) {
                    .low => .{ self.outputs.len, 0 },
                    .high => .{ 0, self.outputs.len },
                };
            },
            .flip_flop => |*ff| {
                switch (signal) {
                    .high => return .{ 0, 0 },
                    .low => {
                        const sending: Signal = switch (ff.state) {
                            .off => .high,
                            .on => .low,
                        };
                        for (self.outputs) |output| {
                            try pending_sends.push(.{
                                .sender = self,
                                .target = output,
                                .signal = sending,
                            });
                        }
                        ff.*.state = if (ff.state == .off) .on else .off;
                        return switch (sending) {
                            .low => .{ self.outputs.len, 0 },
                            .high => .{ 0, self.outputs.len },
                        };
                    },
                }
            },
            .conjunction => |*c| {
                for (c.inputs.items) |*input| {
                    if (!std.mem.eql(u8, &input.id, &sender.id)) continue;
                    input.*.signal = signal;
                }

                const sending: Signal = for (c.inputs.items) |input| {
                    if (input.signal == .low) break .high;
                } else .low;

                for (self.outputs) |output| {
                    try pending_sends.push(.{
                        .sender = self,
                        .target = output,
                        .signal = sending,
                    });
                }
                return switch (sending) {
                    .low => .{ self.outputs.len, 0 },
                    .high => .{ 0, self.outputs.len },
                };
            },
        }
        // unreachable;
    }
};

const PendingSend = struct {
    sender: *Module,
    target: *Module,
    signal: Signal,
};

const ModuleStateGenerator = struct {
    const Self = @This();

    allocator: Allocator,
    modules: *[]Module,
    state_len: usize,

    pub fn init(modules: *[]Module, allocator: Allocator) ModuleStateGenerator {
        var len: usize = 0;

        for (modules.*) |module| {
            switch (module.class) {
                .flip_flop => len += 1,
                .conjunction => |c| len += c.inputs.items.len,
                .broadcaster => {},
            }
        }

        return .{
            .allocator = allocator,
            .modules = modules,
            .state_len = len,
        };
    }

    pub fn captureState(self: Self) ![]bool {
        var ret = try self.allocator.alloc(bool, self.state_len);

        var i: usize = 0;
        for (self.modules.*) |module| {
            switch (module.class) {
                .flip_flop => |ff| {
                    ret[i] = switch (ff.state) {
                        .off => false,
                        .on => true,
                    };
                    i += 1;
                },
                .conjunction => |c| {
                    for (c.inputs.items) |input| {
                        ret[i] = switch (input.signal) {
                            .low => false,
                            .high => true,
                        };
                        i += 1;
                    }
                },
                .broadcaster => {},
            }
        }

        return ret;
    }
};

const ModuleStateContext = struct {
    const Self = @This();

    pub fn hash(self: Self, i: []bool) u64 {
        _ = self;
        return std.hash.Wyhash.hash(0, std.mem.asBytes(&i));
    }

    pub fn eql(self: Self, a: []bool, b: []bool) bool {
        _ = self;
        return std.mem.eql(bool, a, b);
    }
};

// A Queue backed by a ring buffer that's backed by an ArrayList!
// =============================================================================
pub fn RingQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        read_idx: usize,
        write_idx: usize,
        len: usize,
        backing_list: ArrayList(T),

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .read_idx = 0,
                .write_idx = 0,
                .len = 0,
                .backing_list = ArrayList(T).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.backing_list.deinit();
        }

        pub fn push(self: *Self, item: T) !void {
            // Check if we need to resize.
            if (self.backing_list.capacity == self.len) {
                try self.expandBackingList();
            }

            self.backing_list.items[self.write_idx] = item;

            self.write_idx += 1;
            self.write_idx %= self.backing_list.capacity;
            self.len += 1;
        }

        pub fn pop(self: *Self) ?T {
            if (self.len == 0) {
                return null;
            }

            const ret = self.backing_list.items[self.read_idx];

            self.read_idx += 1;
            self.read_idx %= self.backing_list.capacity;
            self.len -= 1;

            return ret;
        }

        pub fn expandBackingList(self: *Self) !void {
            const initial_capacity = self.backing_list.capacity;

            try self.backing_list.ensureTotalCapacity(initial_capacity + 1);
            self.backing_list.expandToCapacity();

            // If the write idx is less than the read idx, it means the write index has wrapped,
            // and we need to reorder items in the backing list to unwrap the write pointer.
            if (self.write_idx <= self.read_idx) {
                // FIXME: Shouldn't need to assert that we have enough room after the read_idx to
                //        fit from [0..write_idx+1]. This should be guaranteed by the
                //        `ensureTotalCapacity` call above.
                const unused_capacity = self.backing_list.capacity - self.len;
                std.debug.assert(unused_capacity > self.write_idx);

                @memcpy(
                    self.backing_list.items[initial_capacity .. initial_capacity + self.write_idx],
                    self.backing_list.items[0..self.write_idx],
                );

                self.write_idx = initial_capacity + self.write_idx;
            }
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.read_idx = 0;
            self.write_idx = 0;
            self.len = 0;
        }

        pub fn clearAndFree(self: *Self) void {
            self.backing_list.clearAndFree();
            self.read_idx = 0;
            self.write_idx = 0;
            self.len = 0;
        }
    };
}
