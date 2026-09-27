const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

// ============================================================================
// 1. Hardware Specification & Wire Protocol
// ============================================================================

const IRO_VID: u16 = 0x2516; // Cooler Master HID
const IRO_PID: u16 = 0x014d; // AMD RX 6800 / 6800XT Reference
const IRO_IFACE: i32 = 1; // RGB Control Interface
const PKT_SIZE: usize = 65;
const MAX_HIDRAW: u32 = 64;
const HIDIOCGRAWINFO: usize = 0x80084803;

const HidrawDevinfo = extern struct {
    bustype: u32,
    vendor: i16,
    product: i16,
};

pub const PacketSimple = extern struct {
    report_id: u8 = 0x00,
    cmd: u8,
    sub: u8,
    pad: [62]u8 = [_]u8{0} ** 62,
};

pub const PacketColourConfig = extern struct {
    report_id: u8 = 0x00,
    cmd: u8 = 0x51,
    sub: u8 = 0xa0,
    p0: u8 = 0x01,
    p1: u8 = 0x00,
    p2: u8 = 0x00,
    p3: u8 = 0x03,
    p4: u8 = 0x00,
    p5: u8 = 0x00,
    p6: u8 = 0x05,
    p7: u8 = 0x06,
    modes: [15]u8 = [_]u8{0x00} ** 15, // 0x00: Direct mode
    pad: [39]u8 = [_]u8{0} ** 39,
};

pub const PacketApply = extern struct {
    report_id: u8 = 0x00,
    cmd: u8 = 0x51,
    sub: u8 = 0x28,
    p0: u8 = 0x00,
    p1: u8 = 0x00,
    flag: u8 = 0xe0,
    pad: [59]u8 = [_]u8{0} ** 59,
};

pub const PacketEffect = extern struct {
    report_id: u8 = 0x00,
    cmd: u8 = 0x51,
    sub: u8 = 0x2c,
    p0: u8 = 0x01,
    p1: u8 = 0x00,
    mode: u8 = 0x00, // Mode.direct
    speed: u8 = 0xff,
    random: u8 = 0x00,
    repeat: u8 = 0xff,
    reserved: u8 = 0xff,
    brightness: u8 = 0xff,
    r: u8,
    g: u8,
    b: u8,
    zero_pad: [3]u8 = [_]u8{0} ** 3,
    trail: [48]u8 = [_]u8{0xff} ** 48,
};

pub const Packet = extern union {
    raw: [PKT_SIZE]u8,
    simple: PacketSimple,
    colour_config: PacketColourConfig,
    apply: PacketApply,
    effect: PacketEffect,
};

comptime {
    std.debug.assert(@sizeOf(Packet) == PKT_SIZE);
    std.debug.assert(@sizeOf(PacketSimple) == PKT_SIZE);
    std.debug.assert(@sizeOf(PacketColourConfig) == PKT_SIZE);
    std.debug.assert(@sizeOf(PacketApply) == PKT_SIZE);
    std.debug.assert(@sizeOf(PacketEffect) == PKT_SIZE);
}

// ============================================================================
// 2. Presets & Colour Parsing
// ============================================================================

const Preset = struct {
    name: []const u8,
    rgb: [3]u8,
};

const presets = [_]Preset{
    .{ .name = "blue", .rgb = .{ 0x00, 0x00, 0xff } },
    .{ .name = "pink", .rgb = .{ 0xff, 0x40, 0x88 } },
    .{ .name = "red", .rgb = .{ 0xff, 0x00, 0x00 } },
    .{ .name = "white", .rgb = .{ 0xff, 0xff, 0xff } },
    .{ .name = "warm-white", .rgb = .{ 0xff, 0xd0, 0xa0 } },
    .{ .name = "green", .rgb = .{ 0x00, 0xff, 0x00 } },
    .{ .name = "cyan", .rgb = .{ 0x00, 0xff, 0xff } },
    .{ .name = "purple", .rgb = .{ 0x99, 0x00, 0xff } },
    .{ .name = "orange", .rgb = .{ 0xff, 0x66, 0x00 } },
    .{ .name = "yellow", .rgb = .{ 0xff, 0xee, 0x00 } },
};

fn parseHexRgb(s: []const u8) ?[3]u8 {
    const raw = if (std.mem.startsWith(u8, s, "#")) s[1..] else s;
    if (raw.len != 6) return null;
    const v = std.fmt.parseInt(u24, raw, 16) catch return null;
    return .{
        @intCast((v >> 16) & 0xff),
        @intCast((v >> 8) & 0xff),
        @intCast(v & 0xff),
    };
}

fn parseColor(s: []const u8) ?[3]u8 {
    for (presets) |p| {
        if (std.ascii.eqlIgnoreCase(s, p.name)) return p.rgb;
    }
    return parseHexRgb(s);
}

fn parseBrightness(s: []const u8) ?u8 {
    if (std.mem.endsWith(u8, s, "%")) {
        const pct_str = s[0 .. s.len - 1];
        const pct = std.fmt.parseFloat(f64, pct_str) catch return null;
        if (pct < 0.0 or pct > 100.0) return null;
        return @intFromFloat(std.math.clamp(pct / 100.0 * 255.0 + 0.5, 0.0, 255.0));
    }
    const val = std.fmt.parseInt(u16, s, 0) catch return null;
    return @intCast(std.math.clamp(val, 0, 255));
}

// ============================================================================
// 3. Transport & Hardware Operations
// ============================================================================

fn hidSend(fd: posix.fd_t, pkt: *const Packet) bool {
    const rc = linux.write(fd, &pkt.raw, PKT_SIZE);
    return linux.errno(rc) == .SUCCESS and rc == PKT_SIZE;
}

fn hidDrain(fd: posix.fd_t, timeout_ms: i32) void {
    var p = [1]linux.pollfd{.{ .fd = fd, .events = linux.POLL.IN, .revents = 0 }};
    if (linux.poll(&p, 1, timeout_ms) > 0) {
        var buf: [PKT_SIZE]u8 = undefined;
        _ = linux.read(fd, &buf, PKT_SIZE);
    }
}

fn hidSendRecv(fd: posix.fd_t, pkt: *const Packet) bool {
    if (!hidSend(fd, pkt)) return false;
    hidDrain(fd, 250);
    return true;
}

fn setOff(fd: posix.fd_t) bool {
    const pkt = Packet{ .simple = .{ .cmd = 0x41, .sub = 0x43 } };
    return hidSend(fd, &pkt);
}

fn setStatic(fd: posix.fd_t, r: u8, g: u8, b: u8, brightness: u8) bool {
    const pkt_enable = Packet{ .simple = .{ .cmd = 0x41, .sub = 0x80 } };
    if (!hidSendRecv(fd, &pkt_enable)) return false;

    const pkt_effect = Packet{
        .effect = .{
            .brightness = brightness,
            .r = r,
            .g = g,
            .b = b,
        },
    };
    if (!hidSend(fd, &pkt_effect)) return false;

    const pkt_config = Packet{ .colour_config = .{} };
    if (!hidSendRecv(fd, &pkt_config)) return false;

    const pkt_apply = Packet{ .apply = .{} };
    return hidSendRecv(fd, &pkt_apply);
}

// ============================================================================
// 4. Device Discovery
// ============================================================================

fn getInterfaceNumber(node_idx: u32) i32 {
    var pbuf: [64]u8 = undefined;
    const path = std.fmt.bufPrintZ(&pbuf, "/sys/class/hidraw/hidraw{d}/device/../bInterfaceNumber", .{node_idx}) catch return -1;
    const fd_rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY }, 0);
    if (linux.errno(fd_rc) != .SUCCESS) return -1;
    const fd: posix.fd_t = @intCast(fd_rc);
    defer _ = linux.close(fd);

    var ibuf: [16]u8 = undefined;
    const n = linux.read(fd, &ibuf, ibuf.len);
    if (linux.errno(n) != .SUCCESS or n <= 0) return -1;
    const s = std.mem.trim(u8, ibuf[0..@intCast(n)], " \r\n");
    return std.fmt.parseInt(i32, s, 10) catch -1;
}

fn openDevice() ?posix.fd_t {
    for (0..MAX_HIDRAW) |i| {
        var pbuf: [32]u8 = undefined;
        const path = std.fmt.bufPrintZ(&pbuf, "/dev/hidraw{d}", .{i}) catch continue;
        const fd_rc = linux.open(path.ptr, .{ .ACCMODE = .RDWR }, 0);
        if (linux.errno(fd_rc) != .SUCCESS) continue;
        const fd: posix.fd_t = @intCast(fd_rc);

        var info: HidrawDevinfo = undefined;
        if (linux.ioctl(fd, HIDIOCGRAWINFO, @intFromPtr(&info)) != 0 or
            @as(u16, @bitCast(info.vendor)) != IRO_VID or
            @as(u16, @bitCast(info.product)) != IRO_PID)
        {
            _ = linux.close(fd);
            continue;
        }

        if (getInterfaceNumber(@intCast(i)) == IRO_IFACE) {
            return fd;
        }
        _ = linux.close(fd);
    }
    return null;
}

// ============================================================================
// 5. CLI & Entry Point
// ============================================================================

fn usage() void {
    std.debug.print(
        \\rx6800xt - RGB control for reference AMD RX 6800/6800XT (2516:014d)
        \\
        \\usage:
        \\  rx6800xt set <colour> [brightness]
        \\  rx6800xt <colour> [brightness]
        \\  rx6800xt off
        \\
        \\brightness:
        \\  0-255 (e.g. 128) or 0-100% (e.g. 50%, default 100%)
        \\
        \\presets:
        \\  blue, pink, red, white, warm-white, green, cyan, purple, orange, yellow
        \\  (or any 6-char hex like FF4080 or #FF4080)
        \\
        \\examples:
        \\  rx6800xt blue
        \\  rx6800xt pink 50%
        \\  rx6800xt set white 128
        \\  rx6800xt off
        \\
    , .{});
}

pub fn main(init: std.process.Init.Minimal) !u8 {
    const args = init.args.vector;
    if (args.len < 2) {
        usage();
        return 2;
    }

    const first = std.mem.span(args[1]);
    if (std.mem.eql(u8, first, "-h") or std.mem.eql(u8, first, "--help")) {
        usage();
        return 0;
    }

    const fd = openDevice() orelse {
        std.debug.print("error: RX 6800/6800XT RGB controller (2516:014d) not found\n", .{});
        return 1;
    };
    defer _ = linux.close(fd);

    if (std.mem.eql(u8, first, "off")) {
        return if (setOff(fd)) 0 else 1;
    }

    var color_arg: ?[]const u8 = null;
    var brightness_arg: ?[]const u8 = null;

    if (std.mem.eql(u8, first, "set")) {
        if (args.len < 3) {
            usage();
            return 2;
        }
        color_arg = std.mem.span(args[2]);
        if (args.len >= 4) brightness_arg = std.mem.span(args[3]);
    } else {
        color_arg = first;
        if (args.len >= 3) brightness_arg = std.mem.span(args[2]);
    }

    if (color_arg) |col_str| {
        const rgb = parseColor(col_str) orelse {
            std.debug.print("error: unknown colour '{s}' (use preset like blue, pink, red, white or hex RRGGBB)\n", .{col_str});
            return 2;
        };

        const brightness: u8 = if (brightness_arg) |b_str|
            parseBrightness(b_str) orelse {
                std.debug.print("error: invalid brightness '{s}' (expected 0-255 or 0-100%)\n", .{b_str});
                return 2;
            }
        else
            255;

        return if (setStatic(fd, rgb[0], rgb[1], rgb[2], brightness)) 0 else 1;
    }

    usage();
    return 2;
}
