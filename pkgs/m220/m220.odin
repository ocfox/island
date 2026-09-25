package main

import "core:flags"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:sys/posix"
import "core:time"

// ============================================================================
// 1. Hardware Specification & Wire Protocol
// ============================================================================

USB_PID_WIRED         :: "248A"
USB_PID_WIRELESS      :: "249A"
USB_INTERFACE_CFG     :: ":1.2"
USB_INTERFACE_CFG_ALT :: "MI_02"

CMD_SET_RATE      :: 0x02
CMD_SET_DPI       :: 0x03
CMD_SET_DEBOUNCE  :: 0x07
CMD_FACTORY_RESET :: 0x09
CMD_GET_TELEMETRY :: 0x10
CMD_GET_RATE      :: 0x12
CMD_GET_DPI       :: 0x13
CMD_GET_PERF      :: 0x17

DPI_MIN          :: 50
DPI_MAX          :: 12000
DPI_STEP         :: 50
STAGES_MAX       :: 6
DEBOUNCE_MIN_MS  :: 2
DEBOUNCE_MAX_MS  :: 20

DEFAULT_STAGES   :: [6]int{800, 1200, 2000, 5000, 8000, 12000}
DEFAULT_STAGE    :: 1
DEFAULT_RATE     :: 1000
DEFAULT_DEBOUNCE :: 8

CONN_WIRED_TYPE  :: 0x17
CONN_WIRED_FLAG  :: 0x03

Report :: [32]u8

checksum :: proc(data: []u8) -> (sum: u8) {
	for b in data do sum += b
	return
}

Packet_Header :: struct #packed {
	dev_id: u8,
	seq:    u8,
	len:    u8,
}

Dpi_Stage_Wire :: struct #packed {
	x: u16le,
	y: u16le,
}

Rate_Payload :: struct #packed {
	header: Packet_Header,
	code:   u8,
}

Debounce_Payload :: struct #packed {
	header:    Packet_Header,
	sub_id:    u8,
	sub_type:  u8,
	param_len: u8,
	ms:        u8,
	reserved:  u8,
}

Dpi_Payload :: struct #packed {
	header: Packet_Header,
	sel:    u8,
	stages: [6]Dpi_Stage_Wire,
}

Button_Binding :: struct #packed {
	page: u8,
	code: u8,
	ext:  u8,
}

Reset_Payload :: struct #packed {
	header:  Packet_Header,
	buttons: [6]Button_Binding,
}

DEFAULT_BUTTONS :: [6]Button_Binding{
	{0x10, 0x01, 0x00}, // Button 1: Left Click
	{0x10, 0x02, 0x00}, // Button 2: Right Click
	{0x10, 0x04, 0x00}, // Button 3: Middle Click
	{0x10, 0x08, 0x00}, // Button 4: Back
	{0x10, 0x10, 0x00}, // Button 5: Forward
	{0x40, 0x01, 0x00}, // Button 6: DPI Cycle
}

TEMPLATE_RATE :: Rate_Payload{
	header = {dev_id = 0x00, seq = 0x01, len = 0x01},
	code   = 0,
}

TEMPLATE_DEBOUNCE :: Debounce_Payload{
	header    = {dev_id = 0x00, seq = 0x01, len = 0x05},
	sub_id    = 0x1E,
	sub_type  = 0x01,
	param_len = 0x01,
	ms        = 0,
	reserved  = 0x00,
}

TEMPLATE_DPI :: Dpi_Payload{
	header = {dev_id = 0x00, seq = 0x01, len = 0x19},
	sel    = 0,
	stages = {},
}

TEMPLATE_RESET :: Reset_Payload{
	header  = {dev_id = 0x00, seq = 0x01, len = 0x0F},
	buttons = DEFAULT_BUTTONS,
}

Telemetry_Report :: struct #packed {
	cmd:       u8,
	status:    u8,
	reserved1: [6]u8,
	conn_type: u8,
	conn_flag: u8,
	reserved2: [2]u8,
	charging:  u8,
	battery:   u8,
	online:    u8,
	reserved3: [16]u8,
	checksum:  u8,
}

Dpi_Report :: struct #packed {
	cmd:       u8,
	status:    u8,
	reserved1: [2]u8,
	sel:       u8,
	stages:    [6]Dpi_Stage_Wire,
	reserved2: [2]u8,
	checksum:  u8,
}

Rate_Report :: struct #packed {
	cmd:       u8,
	status:    u8,
	reserved1: [2]u8,
	code:      u8,
	reserved2: [26]u8,
	checksum:  u8,
}

Performance_Report :: struct #packed {
	cmd:       u8,
	status:    u8,
	reserved1: [5]u8,
	debounce:  u8,
	reserved2: [23]u8,
	checksum:  u8,
}

Rate_Entry :: struct {
	rate: int,
	code: u8,
}

RATES :: [4]Rate_Entry{
	{1000, 1},
	{500,  2},
	{250,  4},
	{125,  8},
}

// ============================================================================
// 2. High-Level Models & CLI Options
// ============================================================================

Telemetry :: struct {
	model:       string,
	is_wired:    bool,
	battery_pct: int,
	is_charging: bool,
	is_online:   bool,
}

Mouse_State :: struct {
	using telem:  Telemetry,
	has_settings: bool,
	active_stage: int,
	stage_count:  int,
	stages:       [6]int,
	polling_rate: int,
	debounce_ms:  int,
}

Options :: struct {
	battery:  bool   `usage:"print battery percentage"`,
	status:   bool   `usage:"print detailed status"`,
	stages:   string `usage:"set dpi stages (comma-separated, e.g. --stages 800,1600)"`,
	stage:    int    `usage:"switch active stage (1-6)"`,
	dpi:      int    `usage:"set dpi for active stage (50-12000)"`,
	rate:     int    `usage:"set polling rate (125, 250, 500, 1000)"`,
	debounce: int    `usage:"set debounce delay in ms (2-20)"`,
	reset:    bool   `usage:"restore factory defaults"`,
	verbose:  bool   `usage:"debug output"`,
}

// ============================================================================
// 3. Parsing & Device Discovery
// ============================================================================

parse_stages :: proc(s: string) -> (stages: [6]int, count: int, ok: bool) {
	if len(s) == 0 do return stages, 0, false
	rem := s
	for len(rem) > 0 {
		if count >= STAGES_MAX do return stages, 0, false
		token: string
		comma_idx := strings.index_byte(rem, u8(44))
		if comma_idx >= 0 {
			token = strings.trim_space(rem[:comma_idx])
			rem = rem[comma_idx + 1:]
		} else {
			token = strings.trim_space(rem)
			rem = ""
		}
		if len(token) == 0 do continue
		val, conv_ok := strconv.parse_int(token)
		if !conv_ok do return stages, 0, false
		stages[count] = val
		count += 1
	}
	return stages, count, count > 0
}

find_device :: proc(buf: ^[32]byte) -> (devnode: string, wired: bool, ok: bool) {
	candidates, err := filepath.glob("/sys/class/hidraw/hidraw*", context.temp_allocator)
	if err != nil do return

	wireless_cand := ""
	for path in candidates {
		link_path := fmt.tprintf("%s/device", path)
		c_link := strings.clone_to_cstring(link_path, context.temp_allocator)
		real_buf: [posix.PATH_MAX]byte
		res := posix.realpath(c_link, &real_buf[0])
		if res == nil do continue
		real_dev := string(res)

		if !strings.contains(real_dev, USB_INTERFACE_CFG) &&
		   !strings.contains(real_dev, ":1.02") &&
		   !strings.contains(real_dev, USB_INTERFACE_CFG_ALT) {
			continue
		}

		uevent_file := fmt.tprintf("%s/device/uevent", path)
		data, read_err := os.read_entire_file(uevent_file, context.temp_allocator)
		if read_err != nil do continue

		content := string(data)
		has_wired := strings.contains(content, "248A") || strings.contains(content, "248a")
		has_wireless := strings.contains(content, "249A") || strings.contains(content, "249a")

		if !has_wired && !has_wireless do continue

		base_name := filepath.base(path)
		if has_wired {
			return fmt.bprintf(buf[:], "/dev/%s", base_name), true, true
		} else if wireless_cand == "" {
			wireless_cand = base_name
		}
	}

	if wireless_cand != "" {
		return fmt.bprintf(buf[:], "/dev/%s", wireless_cand), false, true
	}
	return "", false, false
}

// ============================================================================
// 4. Low-Level HID Communication
// ============================================================================

transact :: proc(f: ^os.File, cmd: u8, body: []u8 = nil, verbose := false) -> (res: Report, ok: bool) {
	req: Report
	req[0] = cmd
	if len(body) > 0 do copy(req[1:31], body)
	req[31] = checksum(req[4:31])

	for attempt in 1..=3 {
		for {
			pfd := posix.pollfd{fd = posix.FD(os.fd(f)), events = {.IN}}
			if posix.poll(&pfd, 1, 0) <= 0 do break
			dummy: [64]u8
			os.read(f, dummy[:])
		}

		if verbose do fmt.eprintfln("[debug] tx 0x%02x (try %d/3)", cmd, attempt)
		os.write(f, req[:])

		deadline := time.time_add(time.now(), time.Second)

		for time.diff(time.now(), deadline) > 0 {
			remaining := time.diff(time.now(), deadline)
			ms := i32(time.duration_milliseconds(remaining))
			if ms <= 0 do break

			pfd := posix.pollfd{fd = posix.FD(os.fd(f)), events = {.IN}}
			if posix.poll(&pfd, 1, ms) > 0 {
				rx: [64]u8
				n, _ := os.read(f, rx[:])
				if n >= 32 && rx[0] == cmd {
					if rx[1] == 0 {
						copy(res[:], rx[:32])
						return res, true
					}
					if verbose do fmt.eprintfln("[debug] cmd 0x%02x non-zero status: 0x%02x", cmd, rx[1])
					break
				}
			}
		}
		time.sleep(60 * time.Millisecond)
	}
	return res, false
}

// ============================================================================
// 5. High-Level Query & Write Operations
// ============================================================================

read_telemetry :: proc(f: ^os.File, verbose := false) -> (t: Telemetry, ok: bool) {
	raw, h_ok := transact(f, CMD_GET_TELEMETRY, nil, verbose)
	if !h_ok do return t, false

	rep := transmute(Telemetry_Report)raw
	t.model = "M220"
	t.is_wired = (rep.conn_type == CONN_WIRED_TYPE || rep.conn_flag == CONN_WIRED_FLAG)
	t.is_charging = (rep.charging != 0)
	t.battery_pct = clamp(int(rep.battery), 0, 100)
	t.is_online = (rep.online != 0)
	return t, true
}

read_state :: proc(f: ^os.File, verbose := false) -> (st: Mouse_State, ok: bool) {
	st.telem = read_telemetry(f, verbose) or_return
	st.active_stage = 1
	st.stage_count = 6
	st.stages = DEFAULT_STAGES
	st.polling_rate = DEFAULT_RATE
	st.debounce_ms = DEFAULT_DEBOUNCE

	if !st.is_wired do return st, true

	// Read DPI stages
	if raw, dpi_ok := transact(f, CMD_GET_DPI, nil, verbose); dpi_ok {
		rep := transmute(Dpi_Report)raw
		count := clamp(int(rep.sel & 0x0F), 1, STAGES_MAX)
		st.stage_count = count
		raw_active := int(rep.sel >> 4)
		st.active_stage = (raw_active + 1) if raw_active < count else 1

		for s in 0..<count {
			st.stages[s] = int(rep.stages[s].x) * DPI_STEP
		}
		st.has_settings = true
	}

	// Read polling rate
	if raw, rate_ok := transact(f, CMD_GET_RATE, nil, verbose); rate_ok {
		rep := transmute(Rate_Report)raw
		for entry in RATES {
			if entry.code == rep.code {
				st.polling_rate = entry.rate
				break
			}
		}
	}

	// Read debounce ms
	if raw, perf_ok := transact(f, CMD_GET_PERF, nil, verbose); perf_ok {
		rep := transmute(Performance_Report)raw
		st.debounce_ms = int(rep.debounce)
	}

	return st, true
}

write_rate :: proc(f: ^os.File, rate_hz: int, verbose := false) -> bool {
	code: u8
	found := false
	for entry in RATES {
		if entry.rate == rate_hz {
			code = entry.code
			found = true
			break
		}
	}

	if !found {
		fmt.eprintln("error: polling rate must be one of: 125, 250, 500, 1000")
		return false
	}

	payload := TEMPLATE_RATE
	payload.code = code
	_, success := transact(f, CMD_SET_RATE, mem.any_to_bytes(payload), verbose)
	return success
}

write_debounce :: proc(f: ^os.File, ms: int, verbose := false) -> bool {
	if ms < DEBOUNCE_MIN_MS || ms > DEBOUNCE_MAX_MS {
		fmt.eprintfln("error: debounce must be between %d and %d ms", DEBOUNCE_MIN_MS, DEBOUNCE_MAX_MS)
		return false
	}

	payload := TEMPLATE_DEBOUNCE
	payload.ms = u8(ms)
	_, success := transact(f, CMD_SET_DEBOUNCE, mem.any_to_bytes(payload), verbose)
	return success
}

write_dpi :: proc(f: ^os.File, stages: []int, target_stage: int, verbose := false) -> bool {
	count := len(stages)
	if count < 1 || count > STAGES_MAX || target_stage < 1 || target_stage > count {
		fmt.eprintln("error: invalid stage count (1-6) or target stage")
		return false
	}

	payload := TEMPLATE_DPI
	payload.sel = u8(((target_stage - 1) << 4) | count)

	for dpi, i in stages {
		if dpi < DPI_MIN || dpi > DPI_MAX || dpi % DPI_STEP != 0 {
			fmt.eprintfln("error: dpi %d must be multiple of %d in range %d-%d", dpi, DPI_STEP, DPI_MIN, DPI_MAX)
			return false
		}
		val := u16le(dpi / DPI_STEP)
		payload.stages[i] = {x = val, y = val}
	}

	_, success := transact(f, CMD_SET_DPI, mem.any_to_bytes(payload), verbose)
	return success
}

reset_factory :: proc(f: ^os.File, verbose := false) -> bool {
	transact(f, CMD_FACTORY_RESET, mem.any_to_bytes(TEMPLATE_RESET), verbose)
	write_rate(f, DEFAULT_RATE, verbose)
	write_debounce(f, DEFAULT_DEBOUNCE, verbose)
	default_stages := DEFAULT_STAGES
	write_dpi(f, default_stages[:], DEFAULT_STAGE, verbose)
	return true
}

apply_settings :: proc(f: ^os.File, opt: Options) -> (mutated: bool, ok: bool) {
	if opt.rate > 0 {
		write_rate(f, opt.rate, opt.verbose) or_return
		fmt.printfln("polling rate set to %d Hz", opt.rate)
		mutated = true
	}

	if opt.debounce > 0 {
		write_debounce(f, opt.debounce, opt.verbose) or_return
		fmt.printfln("debounce set to %d ms", opt.debounce)
		mutated = true
	}

	stages_requested, stage_count, stages_ok := parse_stages(opt.stages)
	if len(opt.stages) > 0 && !stages_ok {
		fmt.eprintln("error: invalid stages format (expected e.g. --stages 800,1600)")
		return mutated, false
	}

	if stage_count > 0 || opt.stage > 0 || opt.dpi > 0 {
		st, s_ok := read_state(f, opt.verbose)

		target_stages := st.stages if (s_ok && st.has_settings) else DEFAULT_STAGES
		target_count  := st.stage_count if (s_ok && st.has_settings) else len(DEFAULT_STAGES)
		target_stage  := st.active_stage if (s_ok && st.has_settings) else DEFAULT_STAGE

		if stage_count > 0 {
			target_count = stage_count
			copy(target_stages[:target_count], stages_requested[:stage_count])
			if target_stage > target_count {
				target_stage = 1
			}
		}

		if opt.stage > 0 {
			target_stage = opt.stage
		}

		if opt.dpi > 0 && target_stage <= target_count {
			target_stages[target_stage - 1] = opt.dpi
		}

		write_dpi(f, target_stages[:target_count], target_stage, opt.verbose) or_return
		fmt.printfln("dpi configuration applied (stages: %v, active: %d)", target_stages[:target_count], target_stage)
		mutated = true
	}

	return mutated, true
}

print_status :: proc(st: ^Mouse_State) {
	mode := "USB Wired" if st.is_wired else "2.4G Wireless"
	charge_str := "charging" if st.is_charging else "discharging"
	fmt.printfln("device:       VK M3 Lite [%s]", mode)
	fmt.printfln("battery:      %d%% (%s)", st.battery_pct, charge_str)

	if st.has_settings {
		fmt.printfln("polling_rate: %d Hz", st.polling_rate)
		fmt.printfln("debounce:     %d ms", st.debounce_ms)
		fmt.printfln("stages (%d active):", st.stage_count)
		for dpi, i in st.stages[:st.stage_count] {
			tag := " (active)" if (i + 1 == st.active_stage) else ""
			fmt.printfln("  [%d] %d DPI%s", i + 1, dpi, tag)
		}
	} else {
		fmt.println("settings:     [readback requires wired connection]")
	}
}

// ============================================================================
// 6. Main Entry Point
// ============================================================================

main :: proc() {
	opt: Options
	flags.parse_or_exit(&opt, os.args, .Unix)

	dev_buf: [32]byte
	devnode, _, found := find_device(&dev_buf)
	if !found {
		fmt.eprintln("error: mouse device not found")
		os.exit(1)
	}

	f, err := os.open(devnode, {.Read, .Write, .Non_Blocking})
	if err != nil {
		fmt.eprintfln("error: failed to open %s", devnode)
		os.exit(1)
	}
	defer os.close(f)

	switch {
	case opt.battery:
		telem, ok := read_telemetry(f, opt.verbose)
		if !ok {
			fmt.eprintln("error: failed to read battery")
			os.exit(1)
		}
		charge_suffix := " (charging)" if telem.is_charging else ""
		fmt.printfln("%d%%%s", telem.battery_pct, charge_suffix)

	case opt.reset:
		fmt.println("restoring factory defaults...")
		if reset_factory(f, opt.verbose) {
			fmt.println("reset complete")
		} else {
			fmt.eprintln("reset failed")
			os.exit(1)
		}

	case:
		mutated, ok := apply_settings(f, opt)
		if !ok do os.exit(1)

		if opt.status || !mutated {
			st, s_ok := read_state(f, opt.verbose)
			if !s_ok {
				fmt.eprintln("error: failed to read mouse status")
				os.exit(1)
			}
			print_status(&st)
		}
	}
}
