package main

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

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
