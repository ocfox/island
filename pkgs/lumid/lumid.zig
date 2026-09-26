const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

// ============================================================================
// Constants & Specifications
// ============================================================================

// DDC/CI Protocol (VESA MCCS 2.2 Standard)
const DDC_I2C_ADDR: u8 = 0x37;
const DDC_HOST_ADDR: u8 = 0x51;
const DDC_CMD_GET_VCP: u8 = 0x01;
const DDC_CMD_GET_VCP_REPLY: u8 = 0x02;
const DDC_CMD_SET_VCP: u8 = 0x03;
const DDC_GET_VCP_LEN: u8 = 0x82; // 0x80 | 2 bytes payload
const DDC_SET_VCP_LEN: u8 = 0x84; // 0x80 | 4 bytes payload
const DDC_REPLY_OK: u8 = 0x00;
const DDC_REPLY_MIN_BYTES: usize = 11;
const VCP_FEATURE_BRIGHTNESS: u8 = 0x10;

// Linux Syscalls & Permissions
const I2C_SLAVE: u32 = 0x0703;
const FLOCK_EX: i32 = 2;
const FLOCK_NB: i32 = 4;
const SHM_FILE_PERMS: linux.mode_t = 0o666;
const SHM_MAP_BYTES: usize = 4096;
const STDOUT_FD: posix.fd_t = 1;
const STDERR_FD: posix.fd_t = 2;

// Timing & Thresholds (VESA MCCS required inter-command delay)
const VESA_RESPONSE_DELAY_MS: u64 = 45;
const MS_PER_SECOND: u64 = 1000;
const NS_PER_MS: u64 = 1_000_000;
const MIN_BRIGHTNESS: i32 = 0;
const MAX_BRIGHTNESS: i32 = 100;
const DEFAULT_BRIGHTNESS: u32 = 50;
const MAX_I2C_BUS_PROBE: u32 = 32;
const WAYBAR_SIGNAL: u32 = 8;

// ============================================================================
// OS Primitives
// ============================================================================

fn openFile(path: [:0]const u8, flags: linux.O, mode: linux.mode_t) !posix.fd_t {
    const rc = linux.open(path.ptr, flags, mode);
    return switch (linux.errno(rc)) {
        .SUCCESS => @intCast(rc),
        else => error.OpenFailed,
    };
}

fn write(fd: posix.fd_t, bytes: []const u8) !usize {
    const rc = linux.write(fd, bytes.ptr, bytes.len);
    return switch (linux.errno(rc)) {
        .SUCCESS => rc,
        else => error.WriteFailed,
    };
}

fn read(fd: posix.fd_t, bytes: []u8) !usize {
    const rc = linux.read(fd, bytes.ptr, bytes.len);
    return switch (linux.errno(rc)) {
        .SUCCESS => rc,
        else => error.ReadFailed,
    };
}

fn close(fd: posix.fd_t) void {
    _ = linux.close(fd);
}

fn sleepMs(ms: u64) void {
    const ts = linux.timespec{
        .sec = @intCast(ms / MS_PER_SECOND),
        .nsec = @intCast((ms % MS_PER_SECOND) * NS_PER_MS),
    };
    _ = linux.nanosleep(&ts, null);
}

// ============================================================================
// DDC/CI Hardware Protocol (VESA MCCS 2.2)
// ============================================================================

const SetVcpPacket = extern struct {
    src: u8 = DDC_HOST_ADDR,
    len: u8 = DDC_SET_VCP_LEN,
    cmd: u8 = DDC_CMD_SET_VCP,
    feature: u8 = VCP_FEATURE_BRIGHTNESS,
    val_hi: u8 = 0x00,
    val_lo: u8,
    checksum: u8 = 0,

    pub fn init(val: u8) SetVcpPacket {
        var p: SetVcpPacket = .{ .val_lo = val };
        p.checksum = (DDC_I2C_ADDR << 1) ^ p.src ^ p.len ^ p.cmd ^ p.feature ^ p.val_hi ^ p.val_lo;
        return p;
    }
};

const GetVcpPacket = extern struct {
    src: u8 = DDC_HOST_ADDR,
    len: u8 = DDC_GET_VCP_LEN,
    cmd: u8 = DDC_CMD_GET_VCP,
    feature: u8 = VCP_FEATURE_BRIGHTNESS,
    checksum: u8 = 0,

    pub fn init() GetVcpPacket {
        var p: GetVcpPacket = .{};
        p.checksum = (DDC_I2C_ADDR << 1) ^ p.src ^ p.len ^ p.cmd ^ p.feature;
        return p;
    }
};

const VcpReply = extern struct {
    src: u8,
    len: u8,
    cmd: u8,
    result: u8,
    feature: u8,
    vcp_type: u8,
    max_hi: u8,
    max_lo: u8,
    cur_hi: u8,
    cur_lo: u8,
    checksum: u8,
};

// Comptime validation of protocol frame layouts
comptime {
    std.debug.assert(@sizeOf(SetVcpPacket) == 7);
    std.debug.assert(@sizeOf(GetVcpPacket) == 5);
    std.debug.assert(@sizeOf(VcpReply) == 11);
}

const Display = struct {
    fd: posix.fd_t,

    pub fn open(connector: []const u8) !Display {
        const bus = findI2cBus(connector) orelse return error.BusNotFound;
        var path_buf: [32]u8 = undefined;
        const dev_path = try std.fmt.bufPrintZ(&path_buf, "/dev/i2c-{d}", .{bus});

        const fd = try openFile(dev_path, .{ .ACCMODE = .RDWR, .CLOEXEC = true }, 0);
        errdefer close(fd);

        if (linux.ioctl(fd, I2C_SLAVE, DDC_I2C_ADDR) != 0) {
            return error.I2cSlaveFailed;
        }
        return .{ .fd = fd };
    }

    pub fn deinit(self: Display) void {
        close(self.fd);
    }

    pub fn getBrightness(self: Display) !u8 {
        const req = GetVcpPacket.init();
        _ = try write(self.fd, std.mem.asBytes(&req));

        sleepMs(VESA_RESPONSE_DELAY_MS);

        // SAFETY: buffer is populated by the subsequent read call
        var reply: VcpReply = undefined;
        const n = try read(self.fd, std.mem.asBytes(&reply));
        if (n >= DDC_REPLY_MIN_BYTES and reply.cmd == DDC_CMD_GET_VCP_REPLY and reply.result == DDC_REPLY_OK and reply.feature == VCP_FEATURE_BRIGHTNESS) {
            return reply.cur_lo;
        }
        return error.InvalidDdcReply;
    }

    pub fn setBrightness(self: Display, val: u8) !void {
        const pkt = SetVcpPacket.init(val);
        _ = try write(self.fd, std.mem.asBytes(&pkt));
    }
};

fn findI2cBus(connector: []const u8) ?u32 {
    for (0..MAX_I2C_BUS_PROBE) |bus_idx| {
        var path_buf: [64]u8 = undefined;
        const p = std.fmt.bufPrintZ(&path_buf, "/sys/class/drm/{s}/i2c-{d}", .{ connector, bus_idx }) catch continue;
        if (openFile(p, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0)) |ifd| {
            close(ifd);
            return @intCast(bus_idx);
        } else |_| {}
    }
    return null;
}

// ============================================================================
// Lock-free Atomic Shared Memory & Worker
// ============================================================================

const State = extern struct {
    target: u32,
    hw: u32,
    initialized: u32,
};

comptime {
    std.debug.assert(@sizeOf(State) == 12);
}

fn getMmapState(connector: []const u8) *State {
    var shm_path_buf: [64]u8 = undefined;
    const shm_path = std.fmt.bufPrintZ(&shm_path_buf, "/dev/shm/lumid-{s}.state", .{connector}) catch "/dev/shm/lumid.state";

    const fd = openFile(shm_path, .{ .ACCMODE = .RDWR, .CREAT = true, .CLOEXEC = true }, SHM_FILE_PERMS) catch {
        const S = struct {
            var fallback = State{ .target = DEFAULT_BRIGHTNESS, .hw = DEFAULT_BRIGHTNESS, .initialized = 1 };
        };
        return &S.fallback;
    };
    defer close(fd);

    _ = linux.ftruncate(fd, SHM_MAP_BYTES);

    const addr = linux.mmap(null, SHM_MAP_BYTES, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, fd, 0);
    const ptr: [*]align(@alignOf(State)) u8 = @ptrFromInt(addr);
    const state: *State = @ptrCast(ptr);

    // One-time hardware initialization
    if (@cmpxchgStrong(u32, &state.initialized, 0, 1, .seq_cst, .seq_cst) == null) {
        var initial_val: u8 = DEFAULT_BRIGHTNESS;
        if (Display.open(connector)) |disp| {
            defer disp.deinit();
            initial_val = disp.getBrightness() catch DEFAULT_BRIGHTNESS;
        } else |_| {}
        @atomicStore(u32, &state.hw, initial_val, .seq_cst);
        @atomicStore(u32, &state.target, initial_val, .seq_cst);
    }
    return state;
}

const Lock = struct {
    fd: posix.fd_t,

    pub fn tryAcquire(connector: []const u8) ?Lock {
        var lock_path_buf: [64]u8 = undefined;
        const lock_path = std.fmt.bufPrintZ(&lock_path_buf, "/dev/shm/lumid-{s}.lock", .{connector}) catch return null;

        const fd = openFile(lock_path, .{ .ACCMODE = .RDWR, .CREAT = true, .CLOEXEC = true }, SHM_FILE_PERMS) catch return null;
        if (linux.flock(fd, FLOCK_EX | FLOCK_NB) != 0) {
            close(fd);
            return null;
        }
        return .{ .fd = fd };
    }

    pub fn deinit(self: Lock) void {
        close(self.fd);
    }
};

fn runWorker(lock: Lock, connector: []const u8) void {
    defer lock.deinit();

    const display = Display.open(connector) catch return;
    defer display.deinit();

    const state = getMmapState(connector);

    while (true) {
        const target = @atomicLoad(u32, &state.target, .seq_cst);
        const hw = @atomicLoad(u32, &state.hw, .seq_cst);
        if (target == hw) break;

        display.setBrightness(@intCast(target)) catch break;
        @atomicStore(u32, &state.hw, target, .seq_cst);

        sleepMs(VESA_RESPONSE_DELAY_MS);
    }
}

fn notifyWaybar() void {
    const pid = linux.fork();
    if (pid == 0) {
        var sig_arg_buf: [16]u8 = undefined;
        const sig_arg = std.fmt.bufPrintZ(&sig_arg_buf, "-RTMIN+{d}", .{WAYBAR_SIGNAL}) catch "-RTMIN+8";
        const argv = [_:null]?[*:0]const u8{ "pkill", sig_arg.ptr, "waybar", null };
        const envp = [_:null]?[*:0]const u8{null};
        _ = linux.execve("/run/current-system/sw/bin/pkill", &argv, &envp);
        _ = linux.execve("/usr/bin/pkill", &argv, &envp);
        linux.exit(0);
    }
}

// ============================================================================
// Actions & CLI
// ============================================================================

fn handleGet(connector: []const u8) void {
    const state = getMmapState(connector);
    const target = @atomicLoad(u32, &state.target, .seq_cst);

    var out_buf: [16]u8 = undefined;
    const msg = std.fmt.bufPrint(&out_buf, "{d}\n", .{target}) catch return;
    _ = write(STDOUT_FD, msg) catch return;
}

fn handleStep(connector: []const u8, delta: i32) void {
    const state = getMmapState(connector);

    var new_target: u32 = 0;
    while (true) {
        const cur = @atomicLoad(u32, &state.target, .seq_cst);
        const next = std.math.clamp(@as(i32, @intCast(cur)) + delta, MIN_BRIGHTNESS, MAX_BRIGHTNESS);
        new_target = @intCast(next);
        if (@cmpxchgWeak(u32, &state.target, cur, new_target, .seq_cst, .seq_cst) == null) {
            break;
        }
    }

    var out_buf: [16]u8 = undefined;
    const msg = std.fmt.bufPrint(&out_buf, "{d}\n", .{new_target}) catch "";
    _ = write(STDOUT_FD, msg) catch return;

    notifyWaybar();

    if (Lock.tryAcquire(connector)) |lock| {
        const pid = linux.fork();
        if (pid == 0) {
            _ = linux.setsid();
            runWorker(lock, connector);
            linux.exit(0);
        }
        lock.deinit();
    }
}

fn handleSet(connector: []const u8, val: u32) void {
    const state = getMmapState(connector);
    const max_val: u32 = @intCast(MAX_BRIGHTNESS);
    const target = if (val > max_val) max_val else val;
    @atomicStore(u32, &state.target, target, .seq_cst);

    var out_buf: [16]u8 = undefined;
    const msg = std.fmt.bufPrint(&out_buf, "{d}\n", .{target}) catch "";
    _ = write(STDOUT_FD, msg) catch return;

    notifyWaybar();

    if (Lock.tryAcquire(connector)) |lock| {
        const pid = linux.fork();
        if (pid == 0) {
            _ = linux.setsid();
            runWorker(lock, connector);
            linux.exit(0);
        }
        lock.deinit();
    }
}

pub fn main(init: std.process.Init.Minimal) !void {
    var it = init.args.iterate();
    _ = it.next(); // binary

    var connector: ?[]const u8 = null;
    var command: ?[]const u8 = null;
    var param: ?[]const u8 = null;

    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--connector")) {
            if (it.next()) |c| {
                connector = c;
            }
        } else if (command == null) {
            command = arg;
        } else if (param == null) {
            param = arg;
        }
    }

    const conn = connector orelse {
        const err_msg = "error: -c <connector> is required (e.g. lumid -c card1-DP-2 get)\n";
        _ = write(STDERR_FD, err_msg) catch return;
        return error.MissingConnector;
    };

    const cmd = command orelse "get";

    if (std.mem.eql(u8, cmd, "get")) {
        handleGet(conn);
    } else if (std.mem.eql(u8, cmd, "set")) {
        const val_str = param orelse "50";
        const val = std.fmt.parseInt(u32, val_str, 10) catch DEFAULT_BRIGHTNESS;
        handleSet(conn, val);
    } else if (std.mem.eql(u8, cmd, "step")) {
        const delta_str = param orelse "+1";
        const delta = std.fmt.parseInt(i32, delta_str, 10) catch 1;
        handleStep(conn, delta);
    } else if (std.mem.startsWith(u8, cmd, "+") or std.mem.startsWith(u8, cmd, "-")) {
        const delta = std.fmt.parseInt(i32, cmd, 10) catch 1;
        handleStep(conn, delta);
    } else {
        handleGet(conn);
    }
}
