const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // List all .zig files in the src/ directory and add them as executables.
    // Allocator so I can sprintf.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    // TODO: Alert when deinit comes back with Check.leak?
    //       Not actually useful here, but it's a pattern I want to have on hand.
    // defer gpa.deinit();

    const src_dir = try std.fs.cwd().openDir("src", .{ .iterate = true });

    var iter = src_dir.iterateAssumeFirstIteration();
    while (try iter.next()) |entry| {
        if (entry.kind != std.fs.File.Kind.file) {
            continue;
        }

        const suffix = entry.name[entry.name.len - 4 ..];
        if (!std.mem.eql(u8, suffix, ".zig")) {
            continue;
        }

        const basename = entry.name[0 .. entry.name.len - 4];
        const name = try std.fmt.allocPrint(alloc, "AdventOfCode2023:{s}", .{basename});
        const path = try std.fmt.allocPrint(alloc, "src/{s}.zig", .{basename});
        const run_step_name = try std.fmt.allocPrint(alloc, "run:{s}", .{basename});
        const run_step_desc = try std.fmt.allocPrint(alloc, "Run Advent Of Code 2023: {s}", .{basename});
        const test_step_name = try std.fmt.allocPrint(alloc, "test:{s}", .{basename});
        const test_step_desc = try std.fmt.allocPrint(alloc, "Test Advent Of Code 2023: {s}", .{basename});
        defer alloc.free(name);
        defer alloc.free(path);
        defer alloc.free(run_step_name);
        defer alloc.free(run_step_desc);
        defer alloc.free(test_step_name);
        defer alloc.free(test_step_desc);

        // binary exe
        const exe = b.addExecutable(.{
            .name = name,
            .root_source_file = .{ .path = path },
            .target = target,
            .optimize = optimize,
        });
        b.installArtifact(exe);

        // run command
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        // invokable `zig build run:...` step
        const run_step = b.step(run_step_name, run_step_desc);
        run_step.dependOn(&run_cmd.step);

        // test exe
        const exe_unit_tests = b.addTest(.{
            .root_source_file = .{ .path = path },
            .target = target,
            .optimize = optimize,
        });

        // test run command
        const unit_test_cmd = b.addRunArtifact(exe_unit_tests);

        // invokable `zig build test:...` step
        const test_step = b.step(test_step_name, test_step_desc);
        test_step.dependOn(&unit_test_cmd.step);
    }
}
