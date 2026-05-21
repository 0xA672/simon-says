const std = @import("std");

fn findAdalibPath(allocator: std.mem.Allocator, io: std.Io, gnatmake_path: []const u8) ![:0]const u8 {
    const exe_dir = std.fs.path.dirname(gnatmake_path) orelse return error.InvalidPath;
    const gnatls_path = try std.fs.path.join(allocator, &.{ exe_dir, "gnatls" });
    defer allocator.free(gnatls_path);

    const cwd = std.Io.Dir.cwd();
    const tmp = try std.fs.path.join(allocator, &.{ "/tmp", "simon-says-adalib" });
    defer allocator.free(tmp);
    cwd.createDirPath(io, tmp) catch {};
    defer cwd.deleteTree(io, tmp) catch {};

    const out_file = try std.fs.path.join(allocator, &.{ tmp, "gnatls_out.txt" });
    defer allocator.free(out_file);

    var cmd_buf: [4096]u8 = undefined;
    const cmd = try std.fmt.bufPrint(&cmd_buf, "{s} -v > {s} 2>&1", .{ gnatls_path, out_file });
    var child = std.process.spawn(io, .{
        .argv = &.{ "sh", "-c", cmd },
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch return error.AdalibNotFound;
    _ = child.wait(io) catch {};

    const file = cwd.openFile(io, out_file, .{}) catch return error.AdalibNotFound;
    defer file.close(io);
    const meta = try file.stat(io);
    const buf = try allocator.alloc(u8, meta.size);
    defer allocator.free(buf);
    _ = try file.readPositionalAll(io, buf, 0);

    var lines = std.mem.splitScalar(u8, buf[0..meta.size], '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");
        if (std.mem.endsWith(u8, trimmed, "adalib")) {
            return allocator.dupeZ(u8, trimmed);
        }
    }
    return error.AdalibNotFound;
}

fn searchGnatmake(allocator: std.mem.Allocator, io: std.Io) ![:0]const u8 {
    const cwd = std.Io.Dir.cwd();
    const cache_dir = try std.fs.path.join(allocator, &.{ "/tmp", "simon-says-cache" });
    defer allocator.free(cache_dir);
    cwd.createDirPath(io, cache_dir) catch {};
    const cache_path = try std.fs.path.join(allocator, &.{ cache_dir, "gnatmake.path" });
    defer allocator.free(cache_path);

    if (cwd.openFile(io, cache_path, .{})) |file| {
        defer file.close(io);
        const meta = try file.stat(io);
        const buf = try allocator.alloc(u8, meta.size);
        defer allocator.free(buf);
        _ = try file.readPositionalAll(io, buf, 0);
        const cached = std.mem.trimEnd(u8, buf, "\n");

        const run_result = std.process.run(allocator, io, .{ .argv = &.{ cached, "--version" } }) catch null;
        if (run_result) |*res| {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
            return allocator.dupeZ(u8, cached) catch unreachable;
        }
        cwd.deleteFile(io, cache_path) catch {};
    } else |_| {}

    const probe_result = std.process.run(allocator, io, .{
        .argv = &.{ "bash", "-l", "-c", "command -v gnatmake" },
    }) catch null;
    if (probe_result) |*res| {
        const out = std.mem.trimEnd(u8, res.stdout, "\n");
        if (out.len > 0) {
            if (cwd.createFile(io, cache_path, .{})) |file| {
                defer file.close(io);
                file.writeStreamingAll(io, out) catch {};
            } else |_| {}
            const duped = allocator.dupeZ(u8, out) catch unreachable;
            allocator.free(res.stdout);
            allocator.free(res.stderr);
            return duped;
        }
        allocator.free(res.stdout);
        allocator.free(res.stderr);
    }

    const prefixes = [_][]const u8{ "/usr/bin", "/usr/local/bin", "/home/linuxbrew/.linuxbrew/bin" };
    for (prefixes) |dir_path| {
        const full = try std.fs.path.join(allocator, &.{ dir_path, "gnatmake" });
        defer allocator.free(full);
        if (cwd.openFile(io, full, .{})) |file| {
            file.close(io);
            return allocator.dupeZ(u8, full) catch unreachable;
        } else |_| {}
    }

    const prefix_dirs = [_][]const u8{ "/usr/local", "/opt" };
    for (prefix_dirs) |prefix| {
        var prefix_dir = std.Io.Dir.openDirAbsolute(io, prefix, .{}) catch continue;
        defer prefix_dir.close(io);
        var it = prefix_dir.iterate();
        while (try it.next(io)) |entry| {
            if (entry.kind == .directory) {
                const full = try std.fs.path.join(allocator, &.{ prefix, entry.name, "bin", "gnatmake" });
                defer allocator.free(full);
                if (cwd.openFile(io, full, .{})) |file| {
                    file.close(io);
                    return allocator.dupeZ(u8, full) catch unreachable;
                } else |_| {}
            }
        }
    }
    return error.GnatmakeNotFound;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const gnatmake_path = searchGnatmake(allocator, io) catch {
        std.debug.print("GNAT not found.\n", .{});
        std.process.exit(1);
    };
    defer allocator.free(gnatmake_path);

    const cwd = std.Io.Dir.cwd();
    const tmp = try std.fs.path.join(allocator, &.{ "/tmp", "simon-says" });
    defer allocator.free(tmp);
    cwd.createDirPath(io, tmp) catch {};
    defer cwd.deleteTree(io, tmp) catch {};

    const version = blk: {
        const ver_file_path = try std.fs.path.join(allocator, &.{ tmp, "version.txt" });
        defer allocator.free(ver_file_path);

        var cmd_buf: [4096]u8 = undefined;
        const cmd = try std.fmt.bufPrint(&cmd_buf,
            "{s} --version > {s} 2>&1",
            .{ gnatmake_path, ver_file_path },
        );
        const run_result = std.process.run(allocator, io, .{ .argv = &.{ "bash", "-l", "-c", cmd } }) catch null;
        if (run_result) |*r| {
            allocator.free(r.stdout);
            allocator.free(r.stderr);
        }

        const ver_file = cwd.openFile(io, ver_file_path, .{}) catch break :blk try allocator.dupeZ(u8, "unknown");
        defer ver_file.close(io);
        const meta = try ver_file.stat(io);
        const buf = try allocator.alloc(u8, meta.size);
        defer allocator.free(buf);
        _ = try ver_file.readPositionalAll(io, buf, 0);
        const content = buf[0..meta.size];
        var lines = std.mem.splitScalar(u8, content, '\n');
        const first_line = lines.first();
        var parts = std.mem.splitScalar(u8, first_line, ' ');
        _ = parts.first();
        const ver = parts.next() orelse "unknown";
        break :blk try allocator.dupeZ(u8, ver);
    };
    defer allocator.free(version);

    const target = blk: {
        const target_file_path = try std.fs.path.join(allocator, &.{ tmp, "target.txt" });
        defer allocator.free(target_file_path);

        var cmd_buf: [4096]u8 = undefined;
        const cmd = try std.fmt.bufPrint(&cmd_buf,
            "gcc -dumpmachine > {s} 2>&1",
            .{target_file_path},
        );
        const run_result = std.process.run(allocator, io, .{ .argv = &.{ "bash", "-l", "-c", cmd } }) catch null;
        if (run_result) |*r| {
            allocator.free(r.stdout);
            allocator.free(r.stderr);
        }

        const target_file = cwd.openFile(io, target_file_path, .{}) catch {
            const uts = std.posix.uname();
            const arch = if (std.mem.eql(u8, std.mem.sliceTo(&uts.machine, 0), "arm64")) "aarch64" else std.mem.sliceTo(&uts.machine, 0);
            var buf: [256]u8 = undefined;
            const fallback = try std.fmt.bufPrint(&buf, "{s}-apple-darwin{s}", .{ arch, std.mem.sliceTo(&uts.release, 0) });
            break :blk try allocator.dupeZ(u8, fallback);
        };
        defer target_file.close(io);
        const meta = try target_file.stat(io);
        const buf = try allocator.alloc(u8, meta.size);
        defer allocator.free(buf);
        _ = try target_file.readPositionalAll(io, buf, 0);
        const trimmed = std.mem.trimEnd(u8, buf[0..meta.size], "\n");
        break :blk try allocator.dupeZ(u8, trimmed);
    };
    defer allocator.free(target);

    const adalib_path = findAdalibPath(allocator, io, gnatmake_path) catch {
        std.debug.print("Cannot find adalib.\n", .{});
        std.process.exit(1);
    };
    defer allocator.free(adalib_path);
    const adalib_dir = std.fs.path.dirname(adalib_path) orelse {
        std.debug.print("Invalid adalib path.\n", .{});
        std.process.exit(1);
    };
    const adainclude_path = try std.fs.path.join(allocator, &.{ adalib_dir, "adainclude" });
    defer allocator.free(adainclude_path);

    const ada_code =
        \\with Ada.Text_IO; use Ada.Text_IO;
        \\procedure Hello_Simon is
        \\begin
        \\   Put_Line("Hello, Simon.");
        \\end Hello_Simon;
    ;
    var file = try cwd.createFile(io,
        try std.fs.path.join(allocator, &.{ tmp, "hello_simon.adb" }),
        .{},
    );
    defer file.close(io);
    try file.writeStreamingAll(io, ada_code);

    const clock = std.Io.Clock.awake;
    const start = clock.now(io);

    const exe_dir = std.fs.path.dirname(gnatmake_path).?;
    var cmd_buf: [4096]u8 = undefined;
    const compile_cmd = try std.fmt.bufPrint(&cmd_buf,
        "export PATH={s}:$PATH && export ADA_INCLUDE_PATH={s} && export ADA_OBJECTS_PATH={s} && cd {s} && {s} hello_simon.adb",
        .{ exe_dir, adainclude_path, adalib_path, tmp, gnatmake_path },
    );
    var child = try std.process.spawn(io, .{
        .argv = &.{ "bash", "-l", "-c", compile_cmd },
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const term = try child.wait(io);
    const end = clock.now(io);
    const elapsed = start.durationTo(end);
    const elapsed_ns = elapsed.toNanoseconds();
    const total_ms = @as(u64, @intCast(elapsed_ns)) / std.time.ns_per_ms;

    const exit_code = switch (term) { .exited => |code| code, else => @as(u8, 1) };
    const success = exit_code == 0;

    const secs = total_ms / 1000;
    const millis = total_ms % 1000;
    var buf_exit: [16]u8 = undefined;
    var buf_dur: [16]u8 = undefined;

    std.debug.print(
        \\With GNAT, Simon Wright gave Ada a home on every Apple machine.
        \\He answered questions. He fixed builds. He never asked for attention.
        \\
        \\This compilation is a heartbeat.
        \\It runs because he ran the build scripts.
        \\It succeeds because he kept the toolchain alive.
        \\
        \\Thank you, Simon.
        \\
        \\GNAT Health Check
        \\-----------------
        \\Compiler  : GNAT {s}
        \\Target    : {s}
        \\Test unit : hello_simon.adb
        \\Result    : {s}
        \\Exit code : {s}
        \\Duration  : {s}
        \\
        \\Ada is alive.
        \\
        \\Last GNAT macOS build maintained by Simon J. Wright:
        \\https://github.com/simonjwright/building-gcc-macos-native
        \\
    , .{
        version,
        target,
        if (success) "COMPILATION OK" else "COMPILATION FAILED",
        try std.fmt.bufPrint(&buf_exit, "{d:0>9}", .{exit_code}),
        try std.fmt.bufPrint(&buf_dur, "{d:0>6}.{d:0>3}s", .{ secs, millis }),
    });

    if (!success) std.process.exit(1);
}
