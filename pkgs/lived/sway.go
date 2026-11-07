package main

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	ipcGetWorkspaces = 1
	ipcSubscribe     = 2
	ipcGetOutputs    = 3
	ipcGetTree       = 4
)

var irohaIcons = []string{"い", "ろ", "は", "に", "ほ", "へ", "と", "ち", "り", "ぬ"}

type SwaySnapshot struct {
	Workspace string
	App       string
	Activity  string
	ScreenOn  bool
	HDR       bool
}

func findSwaySock() string {
	if s := os.Getenv("SWAYSOCK"); s != "" {
		if _, err := os.Stat(s); err == nil {
			return s
		}
	}
	runtimeDir := os.Getenv("XDG_RUNTIME_DIR")
	if runtimeDir == "" {
		runtimeDir = fmt.Sprintf("/run/user/%d", os.Getuid())
	}
	matches, _ := filepath.Glob(filepath.Join(runtimeDir, "sway-ipc.*.sock"))
	for _, m := range matches {
		if conn, err := net.DialTimeout("unix", m, 500*time.Millisecond); err == nil {
			conn.Close()
			return m
		}
	}
	return ""
}

func swayRoundTrip(conn net.Conn, msgType uint32, payload []byte) ([]byte, error) {
	var hdr [14]byte
	copy(hdr[0:6], "i3-ipc")
	binary.LittleEndian.PutUint32(hdr[6:10], uint32(len(payload)))
	binary.LittleEndian.PutUint32(hdr[10:14], msgType)
	if _, err := conn.Write(hdr[:]); err != nil {
		return nil, err
	}
	if len(payload) > 0 {
		if _, err := conn.Write(payload); err != nil {
			return nil, err
		}
	}
	return readSwayFrame(conn)
}

func readSwayFrame(r io.Reader) ([]byte, error) {
	var hdr [14]byte
	if _, err := io.ReadFull(r, hdr[:]); err != nil {
		return nil, err
	}
	length := binary.LittleEndian.Uint32(hdr[6:10])
	if length > 16*1024*1024 {
		return nil, fmt.Errorf("sway frame too large: %d", length)
	}
	body := make([]byte, length)
	if _, err := io.ReadFull(r, body); err != nil {
		return nil, err
	}
	return body, nil
}

type swayNode struct {
	Type             string     `json:"type"`
	Name             string     `json:"name"`
	Num              int        `json:"num"`
	Focused          bool       `json:"focused"`
	AppID            string     `json:"app_id"`
	WindowProperties *swayProps `json:"window_properties"`
	Nodes            []swayNode `json:"nodes"`
	FloatingNodes    []swayNode `json:"floating_nodes"`
}

type swayProps struct {
	Class    string `json:"class"`
	Instance string `json:"instance"`
}

type swayOutput struct {
	Name    string `json:"name"`
	Active  bool   `json:"active"`
	Focused bool   `json:"focused"`
	HDR     bool   `json:"hdr"`
}

type swayWorkspace struct {
	Num     int    `json:"num"`
	Name    string `json:"name"`
	Focused bool   `json:"focused"`
}

func workspaceLabel(num int, name string) string {
	if num >= 1 && num <= len(irohaIcons) {
		return irohaIcons[num-1]
	}
	if name != "" {
		return name
	}
	return "い"
}

// sanitizeApp maps raw app_id / X11 class to a privacy-safe app name and activity description.
// Window titles are intentionally never read or transmitted.
func sanitizeApp(raw string) (string, string) {
	lower := strings.ToLower(strings.TrimSpace(raw))
	if lower == "" {
		return "", "resting on desktop"
	}

	switch {
	case strings.Contains(lower, "zen") || strings.Contains(lower, "firefox") || strings.Contains(lower, "chrome") || strings.Contains(lower, "chromium"):
		return "zen", "wandering the web"
	case strings.Contains(lower, "antigravity") || strings.Contains(lower, "zed") || strings.Contains(lower, "code") || strings.Contains(lower, "helix"):
		return "editor", "writing code"
	case strings.Contains(lower, "foot") || strings.Contains(lower, "alacritty") || strings.Contains(lower, "kitty") || strings.Contains(lower, "wezterm"):
		return "foot", "in the terminal"
	case strings.Contains(lower, "blender"):
		return "blender", "sculpting in 3d"
	case strings.HasPrefix(lower, "steam_app_") || lower == "steam" || strings.Contains(lower, "gamescope"):
		return "steam", "playing a game"
	case strings.Contains(lower, "telegram"):
		return "telegram", "chatting"
	case strings.Contains(lower, "vesktop") || strings.Contains(lower, "discord"):
		return "discord", "chatting"
	case strings.Contains(lower, "spotify"):
		return "spotify", "picking music"
	case strings.Contains(lower, "mpv"):
		return "mpv", "watching video"
	case strings.Contains(lower, "nautilus") || strings.Contains(lower, "thunar"):
		return "files", "organizing files"
	case strings.Contains(lower, "swayimg") || strings.Contains(lower, "imv") || strings.Contains(lower, "gimp") || strings.Contains(lower, "krita"):
		return "canvas", "viewing art"
	case strings.Contains(lower, "obs"):
		return "obs", "recording"
	default:
		// Keep only simple alphanumeric token, strip reverse-DNS prefixes
		parts := strings.Split(lower, ".")
		short := parts[len(parts)-1]
		if len(short) > 16 {
			short = short[:16]
		}
		return short, "using " + short
	}
}

func findFocusedLeaf(n *swayNode) *swayNode {
	if n.Focused && len(n.Nodes) == 0 && len(n.FloatingNodes) == 0 && n.Type != "workspace" && n.Type != "output" && n.Type != "root" {
		return n
	}
	for i := range n.FloatingNodes {
		if res := findFocusedLeaf(&n.FloatingNodes[i]); res != nil {
			return res
		}
	}
	for i := range n.Nodes {
		if res := findFocusedLeaf(&n.Nodes[i]); res != nil {
			return res
		}
	}
	return nil
}

func querySwaySnapshot() (SwaySnapshot, error) {
	sock := findSwaySock()
	if sock == "" {
		return SwaySnapshot{Workspace: "い", ScreenOn: true}, fmt.Errorf("SWAYSOCK not found")
	}
	conn, err := net.DialTimeout("unix", sock, 2*time.Second)
	if err != nil {
		return SwaySnapshot{Workspace: "い", ScreenOn: true}, err
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(2 * time.Second))

	snap := SwaySnapshot{
		Workspace: "い",
		Activity:  "resting on desktop",
		ScreenOn:  true,
	}

	// 1. Workspaces
	if wsBytes, err := swayRoundTrip(conn, ipcGetWorkspaces, nil); err == nil {
		var workspaces []swayWorkspace
		if json.Unmarshal(wsBytes, &workspaces) == nil {
			for _, ws := range workspaces {
				if ws.Focused {
					snap.Workspace = workspaceLabel(ws.Num, ws.Name)
					break
				}
			}
		}
	}

	// 2. Outputs (check DP-2 or focused output)
	if outBytes, err := swayRoundTrip(conn, ipcGetOutputs, nil); err == nil {
		var outputs []swayOutput
		if json.Unmarshal(outBytes, &outputs) == nil && len(outputs) > 0 {
			anyActive := false
			for _, o := range outputs {
				if o.Active {
					anyActive = true
				}
				if o.Name == "DP-2" || o.Focused {
					snap.HDR = o.HDR
				}
			}
			snap.ScreenOn = anyActive
		}
	}

	// 3. Tree (focused window app_id)
	if treeBytes, err := swayRoundTrip(conn, ipcGetTree, nil); err == nil {
		var root swayNode
		if json.Unmarshal(treeBytes, &root) == nil {
			if leaf := findFocusedLeaf(&root); leaf != nil {
				rawApp := leaf.AppID
				if rawApp == "" && leaf.WindowProperties != nil {
					rawApp = leaf.WindowProperties.Class
				}
				snap.App, snap.Activity = sanitizeApp(rawApp)
			}
		}
	}

	return snap, nil
}

func watchSwayEvents(notifyCh chan<- struct{}) {
	for {
		sock := findSwaySock()
		if sock == "" {
			time.Sleep(5 * time.Second)
			continue
		}
		conn, err := net.Dial("unix", sock)
		if err != nil {
			time.Sleep(5 * time.Second)
			continue
		}
		subPayload := []byte(`["workspace","window","output","shutdown"]`)
		if _, err := swayRoundTrip(conn, ipcSubscribe, subPayload); err != nil {
			conn.Close()
			time.Sleep(5 * time.Second)
			continue
		}
		log.Printf("[sway] subscribed to IPC events on %s", sock)
		for {
			if _, err := readSwayFrame(conn); err != nil {
				conn.Close()
				break
			}
			select {
			case notifyCh <- struct{}{}:
			default:
			}
		}
		time.Sleep(2 * time.Second)
	}
}
