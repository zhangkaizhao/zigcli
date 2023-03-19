//! Tree(1) in Zig
//! https://linux.die.net/man/1/tree
//!
//! Order:
//! - Files first, directory last
//! - Asc

const std = @import("std");
const simargs = @import("simargs");
const process = std.process;
const fs = std.fs;
const mem = std.mem;
const testing = std.testing;

pub const std_options = struct {
    pub const log_level: std.log.Level = .info;
};

const Mode = enum {
    ASCII,
    BOX,
};

const Position = enum {
    Normal,
    // last file in current dir
    Last,
    UpperNormal,
    // last file is upper dir
    UpperLast,
};

const PREFIX_ARR = [_][4][]const u8{ // mode -> position
    .{ "|--", "\\--", "|  ", "   " },
    .{ "├──", "└──", "│  ", "   " },
};

fn getPrefix(mode: Mode, pos: Position) []const u8 {
    return PREFIX_ARR[@enumToInt(mode)][@enumToInt(pos)];
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const opt = try simargs.parse(allocator, struct {
        mode: Mode = .BOX,
        help: ?bool,

        pub const __shorts__ = .{
            .mode = .m,
            .help = .h,
        };

        pub const __messages__ = .{ .help = "Prints help information", .mode = "line-drawing characters" };
    });
    defer opt.deinit();

    if (opt.args.help) |help| {
        if (help) {
            const stdout = std.io.getStdOut();
            try opt.print_help(stdout.writer(), "[directory]");
            return;
        }
    }

    const root_dir = if (opt.positional_args.items.len == 0)
        "."
    else
        opt.positional_args.items[0];

    var writer = std.io.bufferedWriter(std.io.getStdOut().writer());
    _ = try writer.write(root_dir);
    _ = try writer.write("\n");

    var iter_dir =
        try fs.cwd().openIterableDir(root_dir, .{});
    defer iter_dir.close();

    try walk(allocator, &iter_dir, &writer, opt.args.mode, "");

    try writer.flush();
}

fn stringLessThan(a: []const u8, b: []const u8) bool {
    var i: usize = 0;
    while (i < a.len and i < b.len) {
        if (a[i] != b[i]) {
            return a[i] < b[i];
        }
        i += 1;
    }
    return a.len < b.len;
}

test "testing string lessThan" {
    const testcases = [_]std.meta.Tuple(&[_]type{ []const u8, []const u8, bool }){
        .{ "a", "a", false },
        .{ "a", "aa", true },
        .{ "a", "b", true },
        .{ "b", "a", false },
        .{ "a", "A", false }, // A > a
    };
    for (testcases) |case| {
        try testing.expectEqual(case.@"2", stringLessThan(case.@"0", case.@"1"));
    }
}

fn walk(
    allocator: mem.Allocator,
    iter_dir: *fs.IterableDir,
    writer: anytype,
    mode: Mode,
    prefix: []const u8,
) !void {
    var it = iter_dir.iterate();
    var files = std.ArrayList(fs.IterableDir.Entry).init(allocator);
    while (try it.next()) |entry| {
        const dupe_name = try allocator.dupe(u8, entry.name);
        try files.append(.{ .name = dupe_name, .kind = entry.kind });
    }

    std.sort.sort(fs.IterableDir.Entry, files.items, {}, struct {
        fn lessThan(ctx: void, a: fs.IterableDir.Entry, b: fs.IterableDir.Entry) bool {
            _ = ctx;

            // file < directory
            if (a.kind != b.kind) {
                if (a.kind == .Directory) {
                    return false;
                }
                if (b.kind == .Directory) {
                    return true;
                }
            }

            return stringLessThan(a.name, b.name);
        }
    }.lessThan);

    for (files.items, 0..) |entry, i| {
        _ = try writer.write(prefix);

        if (i < files.items.len - 1) {
            _ = try writer.write(getPrefix(mode, Position.Normal));
        } else {
            _ = try writer.write(getPrefix(mode, Position.Last));
        }
        _ = try writer.write(entry.name);
        _ = try writer.write("\n");
        switch (entry.kind) {
            .Directory => {
                var sub_iter_dir = try iter_dir.dir.openIterableDir(entry.name, .{});
                defer sub_iter_dir.close();

                const new_prefix =
                    if (i < files.items.len - 1)
                    try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, getPrefix(mode, Position.UpperNormal) })
                else
                    try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, getPrefix(mode, Position.UpperLast) });
                try walk(allocator, &sub_iter_dir, writer, mode, new_prefix);
            },
            else => {},
        }
    }
}