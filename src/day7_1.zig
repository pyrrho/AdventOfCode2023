const std = @import("std");
const testing = std.testing;

const Rank = enum {
    high_card, // all cards' labels are distinct: 23456
    one_pair, // two cards share one label, and the other three cards have a different label from the pair and each other: A23A4
    two_pair, // two cards share one label, two other cards share a second label, and the remaining card has a third label: 23432
    three_of_a_kind, // three cards have the same label, and the remaining two cards are each different from any other card in the hand: TTT98
    full_house, // three cards have the same label, and the remaining two cards share a different label: 23332
    four_of_a_kind, // four cards have the same label and one card has a different label: AA8AA
    five_of_a_kind, // all five cards have the same label: AAAAA
};

const Hand = struct {
    cards: []const u8,
    rank: Rank,
    bid: u64,

    pub fn fromCards(cards: []const u8, bid: u64) Hand {
        std.debug.assert(cards.len == 5);

        return Hand{
            .cards = cards,
            .rank = findRank(cards),
            .bid = bid,
        };
    }

    pub fn findRank(cards: []const u8) Rank {
        std.debug.assert(cards.len == 5);

        var sorted: [5]u8 = undefined;
        std.mem.copyForwards(u8, &sorted, cards);
        std.mem.sort(u8, &sorted, {}, std.sort.asc(u8));

        var a: u8 = 1;
        var b: u8 = 0;
        var last = sorted[0];
        for (sorted[1..]) |card| {
            if (card == last) {
                a += 1;
                continue;
            }

            last = card;
            if (a > b) {
                b = a;
                a = 1;
            }
        }

        if (a < b) std.mem.swap(u8, &a, &b);

        return switch (a) {
            5 => Rank.five_of_a_kind,
            4 => Rank.four_of_a_kind,
            3 => switch (b) {
                2 => Rank.full_house,
                else => Rank.three_of_a_kind,
            },
            2 => switch (b) {
                2 => Rank.two_pair,
                else => Rank.one_pair,
            },
            else => Rank.high_card,
        };
    }

    pub fn compare(lhs: Hand, rhs: Hand) i32 {
        if (lhs.rank != rhs.rank) {
            return @as(i32, @intFromEnum(lhs.rank)) - @as(i32, @intFromEnum(rhs.rank));
        }

        for (lhs.cards, rhs.cards) |lhs_card, rhs_card| {
            if (lhs_card == rhs_card) continue;
            return ordered(lhs_card) - ordered(rhs_card);
        }

        return 0;
    }

    pub fn eql(self: Hand, other: Hand) bool {
        return self.compare(other) == 0;
    }
    pub fn lt(self: Hand, other: Hand) bool {
        return self.compare(other) < 0;
    }
    pub fn leq(self: Hand, other: Hand) bool {
        return self.compare(other) <= 0;
    }
    pub fn gt(self: Hand, other: Hand) bool {
        return self.compare(other) > 0;
    }
    pub fn geq(self: Hand, other: Hand) bool {
        return self.compare(other) >= 0;
    }

    pub fn sortAsc(_: void, lhs: Hand, rhs: Hand) bool {
        return lhs.lt(rhs);
    }
    pub fn sortDesc(_: void, lhs: Hand, rhs: Hand) bool {
        return lhs.gt(rhs);
    }

    fn ordered(card: u8) i32 {
        return switch (card) {
            'A' => '9' + 5,
            'K' => '9' + 4,
            'Q' => '9' + 3,
            'J' => '9' + 2,
            'T' => '9' + 1,
            else => @as(i32, @intCast(card)),
        };
    }
};

test "find rank" {
    try testing.expect(Hand.findRank("23456") == Rank.high_card);
    try testing.expect(Hand.findRank("A23A4") == Rank.one_pair);
    try testing.expect(Hand.findRank("23432") == Rank.two_pair);
    try testing.expect(Hand.findRank("TT98T") == Rank.three_of_a_kind);
    try testing.expect(Hand.findRank("23332") == Rank.full_house);
    try testing.expect(Hand.findRank("AA8AA") == Rank.four_of_a_kind);
    try testing.expect(Hand.findRank("AAAAA") == Rank.five_of_a_kind);
}

test "comparing hands" {
    try testing.expect(Hand.compare(Hand.fromCards("23456", 0), Hand.fromCards("23456", 0)) == 0);
    try testing.expect(Hand.compare(Hand.fromCards("23456", 0), Hand.fromCards("23456", 1)) == 0);
    try testing.expect(Hand.compare(Hand.fromCards("23456", 1), Hand.fromCards("23456", 0)) == 0);

    try testing.expect(Hand.fromCards("23456", 0).lt(Hand.fromCards("23457", 0)) == true);
    try testing.expect(Hand.fromCards("23457", 0).lt(Hand.fromCards("23456", 0)) == false);

    try testing.expect(Hand.fromCards("33332", 0).gt(Hand.fromCards("2AAAA", 0)) == true);
    try testing.expect(Hand.fromCards("77888", 0).gt(Hand.fromCards("77788", 0)) == true);

    try testing.expect(Hand.fromCards("234AA", 0).gt(Hand.fromCards("23456", 0)) == true);
    try testing.expect(Hand.fromCards("222AA", 0).gt(Hand.fromCards("22256", 0)) == true);
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const file = try std.fs.cwd().openFile("src/day7_input.txt", .{});
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

    var hands = std.ArrayList(Hand).init(allocator);
    defer {
        for (hands.items) |hand| {
            allocator.free(hand.cards);
        }
        hands.deinit();
    }

    while (true) {
        in_stream.readUntilDelimiterArrayList(&buf, '\n', 1024) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        var tokens = std.mem.tokenizeSequence(u8, buf.items, " ");

        const cards = try std.mem.Allocator.dupe(allocator, u8, tokens.next().?[0..5]);
        const bid = try std.fmt.parseInt(u64, tokens.next().?, 10);

        try hands.append(Hand.fromCards(cards, bid));
    }

    std.mem.sort(Hand, hands.items, {}, Hand.sortAsc);

    var winnings: u64 = 0;
    var rank: u64 = 1;
    for (hands.items) |hand| {
        winnings += hand.bid * rank;
        rank += 1;
    }

    try stdout.print("winnings: {}\n", .{winnings});
}
