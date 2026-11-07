package main

import (
	"context"
	"encoding/binary"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type cpuTimes struct {
	idle  uint64
	total uint64
}

var lastCPU cpuTimes

func readCPULoad() int {
	data, err := os.ReadFile("/proc/stat")
	if err != nil {
		return 0
	}
	lines := strings.SplitN(string(data), "\n", 2)
	if len(lines) == 0 {
		return 0
	}
	fields := strings.Fields(lines[0])
	if len(fields) < 5 || fields[0] != "cpu" {
		return 0
	}
	var total uint64
	var idle uint64
	for i, f := range fields[1:] {
		v, err := strconv.ParseUint(f, 10, 64)
		if err != nil {
			continue
		}
		total += v
		if i == 3 || i == 4 { // idle + iowait
			idle += v
		}
	}
	prev := lastCPU
	lastCPU = cpuTimes{idle: idle, total: total}
	if prev.total == 0 || total <= prev.total {
		return 0
	}
	dTotal := total - prev.total
	dIdle := idle - prev.idle
	if dIdle >= dTotal {
		return 0
	}
	pct := int(((dTotal - dIdle) * 100) / dTotal)
	if pct > 100 {
		pct = 100
	}
	return pct
}

func readGPULoad() int {
	matches, _ := filepath.Glob("/sys/class/drm/card*/device/gpu_busy_percent")
	best := 0
	for _, m := range matches {
		b, err := os.ReadFile(m)
		if err != nil {
			continue
		}
		v, err := strconv.Atoi(strings.TrimSpace(string(b)))
		if err == nil && v > best {
			best = v
		}
	}
	if best > 100 {
		best = 100
	}
	return best
}

// readLumidBrightness reads the target brightness (u32 LE at offset 0)
// from lumid's shared memory state file (/dev/shm/lumid-*.state).
func readLumidBrightness() int {
	paths := []string{"/dev/shm/lumid-card1-DP-2.state"}
	if extra, err := filepath.Glob("/dev/shm/lumid-*.state"); err == nil {
		paths = append(paths, extra...)
	}
	for _, p := range paths {
		b, err := os.ReadFile(p)
		if err == nil && len(b) >= 4 {
			val := int(binary.LittleEndian.Uint32(b[0:4]))
			if val >= 0 && val <= 100 {
				return val
			}
		}
	}
	return 50
}

func readDarkMode() bool {
	ctx, cancel := context.WithTimeout(context.Background(), 800*time.Millisecond)
	defer cancel()
	out, err := exec.CommandContext(ctx, "gsettings", "get", "org.gnome.desktop.interface", "color-scheme").Output()
	if err != nil {
		return true
	}
	return strings.Contains(string(out), "dark")
}

func isSwaylocked() bool {
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return false
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		name := e.Name()
		if len(name) == 0 || name[0] < '0' || name[0] > '9' {
			continue
		}
		comm, err := os.ReadFile(filepath.Join("/proc", name, "comm"))
		if err == nil && strings.TrimSpace(string(comm)) == "swaylock" {
			return true
		}
	}
	return false
}

func notifyPoke() {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_ = exec.CommandContext(
		ctx,
		"notify-send",
		"-a", "live.s4r.in",
		"-t", "4000",
		"✦ live.s4r.in",
		"someone poked you from the dream.",
	).Run()
}
