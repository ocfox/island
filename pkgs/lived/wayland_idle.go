package main

import (
	"encoding/binary"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
	"time"
)

// Pure-Go Wayland wire protocol client for ext-idle-notify-v1.
// Object IDs:
// 1 = wl_display
// 2 = wl_registry
// 3 = wl_callback (sync)
// 4 = wl_seat
// 5 = ext_idle_notifier_v1
// 6 = ext_idle_notification_v1

func waylandSocketPath() (string, error) {
	disp := os.Getenv("WAYLAND_DISPLAY")
	if disp == "" {
		disp = "wayland-1"
	}
	if filepath.IsAbs(disp) {
		return disp, nil
	}
	runtimeDir := os.Getenv("XDG_RUNTIME_DIR")
	if runtimeDir == "" {
		runtimeDir = fmt.Sprintf("/run/user/%d", os.Getuid())
	}
	p := filepath.Join(runtimeDir, disp)
	if _, err := os.Stat(p); err == nil {
		return p, nil
	}
	// Fallback probe wayland-0 / wayland-1
	for _, candidate := range []string{"wayland-1", "wayland-0"} {
		alt := filepath.Join(runtimeDir, candidate)
		if _, err := os.Stat(alt); err == nil {
			return alt, nil
		}
	}
	return p, nil
}

func putWaylandString(buf []byte, s string) []byte {
	strLen := uint32(len(s) + 1) // include NUL terminator
	var tmp [4]byte
	binary.LittleEndian.PutUint32(tmp[:], strLen)
	buf = append(buf, tmp[:]...)
	buf = append(buf, s...)
	buf = append(buf, 0) // NUL
	pad := (4 - (int(strLen) % 4)) % 4
	for range pad {
		buf = append(buf, 0)
	}
	return buf
}

func sendWaylandMsg(w io.Writer, objID uint32, opcode uint16, payload []byte) error {
	size := uint16(8 + len(payload))
	var hdr [8]byte
	binary.LittleEndian.PutUint32(hdr[0:4], objID)
	binary.LittleEndian.PutUint32(hdr[4:8], (uint32(size)<<16)|uint32(opcode))
	if _, err := w.Write(hdr[:]); err != nil {
		return err
	}
	if len(payload) > 0 {
		if _, err := w.Write(payload); err != nil {
			return err
		}
	}
	return nil
}

func sendRegistryBind(w io.Writer, name uint32, iface string, version uint32, newID uint32) error {
	var payload []byte
	var tmp [4]byte
	binary.LittleEndian.PutUint32(tmp[:], name)
	payload = append(payload, tmp[:]...)
	payload = putWaylandString(payload, iface)
	binary.LittleEndian.PutUint32(tmp[:], version)
	payload = append(payload, tmp[:]...)
	binary.LittleEndian.PutUint32(tmp[:], newID)
	payload = append(payload, tmp[:]...)
	return sendWaylandMsg(w, 2, 0, payload)
}

func parseWaylandString(body []byte, offset int) (string, int, bool) {
	if offset+4 > len(body) {
		return "", offset, false
	}
	strLen := int(binary.LittleEndian.Uint32(body[offset : offset+4]))
	offset += 4
	if strLen <= 0 || offset+strLen > len(body) {
		return "", offset, false
	}
	s := string(body[offset : offset+strLen-1])
	padded := (strLen + 3) & ^3
	offset += padded
	return s, offset, true
}

func watchWaylandIdle(timeoutSec int, idleCh chan<- bool) {
	for {
		err := runWaylandIdleSession(uint32(timeoutSec*1000), idleCh)
		if err != nil {
			log.Printf("[wayland-idle] session ended: %v, retrying in 5s", err)
		}
		time.Sleep(5 * time.Second)
	}
}

func runWaylandIdleSession(timeoutMs uint32, idleCh chan<- bool) error {
	sockPath, err := waylandSocketPath()
	if err != nil {
		return err
	}
	conn, err := net.Dial("unix", sockPath)
	if err != nil {
		return err
	}
	defer conn.Close()

	// 1. wl_display.get_registry (new_id = 2)
	var u32 [4]byte
	binary.LittleEndian.PutUint32(u32[:], 2)
	if err := sendWaylandMsg(conn, 1, 1, u32[:]); err != nil {
		return err
	}

	// 2. wl_display.sync (new_id = 3)
	binary.LittleEndian.PutUint32(u32[:], 3)
	if err := sendWaylandMsg(conn, 1, 0, u32[:]); err != nil {
		return err
	}

	var seatName uint32
	var idleNotifierName uint32
	bound := false

	var hdr [8]byte
	for {
		if _, err := io.ReadFull(conn, hdr[:]); err != nil {
			return err
		}
		objID := binary.LittleEndian.Uint32(hdr[0:4])
		sizeAndOp := binary.LittleEndian.Uint32(hdr[4:8])
		size := int(sizeAndOp >> 16)
		opcode := uint16(sizeAndOp & 0xffff)

		if size < 8 {
			return fmt.Errorf("invalid wayland frame size %d", size)
		}
		bodyLen := size - 8
		var body []byte
		if bodyLen > 0 {
			body = make([]byte, bodyLen)
			if _, err := io.ReadFull(conn, body); err != nil {
				return err
			}
		}

		switch objID {
		case 1: // wl_display
			if opcode == 0 && len(body) >= 8 {
				errObj := binary.LittleEndian.Uint32(body[0:4])
				errCode := binary.LittleEndian.Uint32(body[4:8])
				msg, _, _ := parseWaylandString(body, 8)
				return fmt.Errorf("wl_display error on obj %d (code %d): %s", errObj, errCode, msg)
			}
		case 2: // wl_registry
			if opcode == 0 && len(body) >= 8 { // global
				name := binary.LittleEndian.Uint32(body[0:4])
				iface, nextOff, ok := parseWaylandString(body, 4)
				if !ok || nextOff+4 > len(body) {
					continue
				}
				switch iface {
				case "wl_seat":
					if seatName == 0 {
						seatName = name
					}
				case "ext_idle_notifier_v1":
					if idleNotifierName == 0 {
						idleNotifierName = name
					}
				}
			}
		case 3: // wl_callback.done
			if opcode == 0 && !bound {
				if seatName == 0 || idleNotifierName == 0 {
					return fmt.Errorf("missing globals (wl_seat=%d, ext_idle_notifier_v1=%d)", seatName, idleNotifierName)
				}
				// Bind wl_seat -> obj 4
				if err := sendRegistryBind(conn, seatName, "wl_seat", 1, 4); err != nil {
					return err
				}
				// Bind ext_idle_notifier_v1 -> obj 5
				if err := sendRegistryBind(conn, idleNotifierName, "ext_idle_notifier_v1", 1, 5); err != nil {
					return err
				}
				// ext_idle_notifier_v1.get_idle_notification(id=6, timeout=timeoutMs, seat=4)
				var req [12]byte
				binary.LittleEndian.PutUint32(req[0:4], 6)
				binary.LittleEndian.PutUint32(req[4:8], timeoutMs)
				binary.LittleEndian.PutUint32(req[8:12], 4)
				if err := sendWaylandMsg(conn, 5, 1, req[:]); err != nil {
					return err
				}
				bound = true
				log.Printf("[wayland-idle] watching ext-idle-notify-v1 (timeout=%dms)", timeoutMs)
			}
		case 6: // ext_idle_notification_v1
			switch opcode {
			case 0: // idled
				idleCh <- true
			case 1: // resumed
				idleCh <- false
			}
		}
	}
}
