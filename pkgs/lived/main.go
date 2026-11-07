package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"
	"time"
)

func getEnv(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}

func readSecret(secretFlag, secretFileFlag string) string {
	if secretFlag != "" {
		return secretFlag
	}
	file := secretFileFlag
	if file == "" {
		file = os.Getenv("LIVED_SECRET_FILE")
	}
	if file != "" {
		data, err := os.ReadFile(file)
		if err == nil {
			return strings.TrimSpace(string(data))
		}
		log.Printf("warning: failed to read secret file %s: %v", file, err)
	}
	return os.Getenv("LIVED_SECRET")
}

func buildSnapshot(waylandIdle bool, spotify *SpotifyData) PresencePayload {
	sway, _ := querySwaySnapshot()
	locked := isSwaylocked()

	status := "online"
	if waylandIdle || !sway.ScreenOn || locked {
		status = "idle"
	}
	// If actively listening to Spotify while screen is on and unlocked, keep online = true
	online := status == "online" || (spotify != nil && sway.ScreenOn && !locked)

	desktop := &DesktopState{
		Workspace: sway.Workspace,
		Activity:  sway.Activity,
		App:       sway.App,
		ScreenOn:  sway.ScreenOn,
	}

	return PresencePayload{
		Kind:      "state",
		Status:    status,
		Online:    online,
		Spotify:   spotify,
		Desktop:   desktop,
		UpdatedAt: time.Now().UnixMilli(),
	}
}

func ensureSessionEnv() {
	runtimeDir := os.Getenv("XDG_RUNTIME_DIR")
	if runtimeDir == "" {
		runtimeDir = fmt.Sprintf("/run/user/%d", os.Getuid())
		_ = os.Setenv("XDG_RUNTIME_DIR", runtimeDir)
	}
	if os.Getenv("DBUS_SESSION_BUS_ADDRESS") == "" {
		busPath := runtimeDir + "/bus"
		if _, err := os.Stat(busPath); err == nil {
			_ = os.Setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path="+busPath)
		}
	}
}

func main() {
	ensureSessionEnv()
	endpointFlag := flag.String("endpoint", getEnv("LIVED_ENDPOINT", "wss://live.s4r.in/presence/push"), "WebSocket push endpoint")
	secretFlag := flag.String("secret", "", "Bearer secret for authentication")
	secretFileFlag := flag.String("secret-file", "", "Path to file containing Bearer secret")
	idleFlag := flag.Int("idle-timeout", 300, "Idle timeout in seconds before marking status as idle")
	printFlag := flag.Bool("print", false, "Collect current snapshot once, print JSON to stdout and exit")
	flag.Parse()

	if envIdle := os.Getenv("LIVED_IDLE_SECONDS"); envIdle != "" {
		if iv, err := strconv.Atoi(envIdle); err == nil && iv > 0 {
			*idleFlag = iv
		}
	}

	if *printFlag {
		sp := querySpotifyOnce()
		snap := buildSnapshot(false, sp)
		data, _ := json.MarshalIndent(snap, "", "  ")
		fmt.Println(string(data))
		return
	}

	secret := readSecret(*secretFlag, *secretFileFlag)

	idleCh := make(chan bool, 4)
	swayCh := make(chan struct{}, 4)
	spotifyCh := make(chan *SpotifyData, 8)

	go watchWaylandIdle(*idleFlag, idleCh)
	go watchSwayEvents(swayCh)
	go watchSpotify(spotifyCh)

	waylandIdle := false
	currentSpotify := querySpotifyOnce()

	for {
		ws, err := dialWS(*endpointFlag, secret)
		if err != nil {
			log.Printf("[lived] connect %s failed: %v (retrying in 5s)", *endpointFlag, err)
		drainLoop:
			for {
				select {
				case waylandIdle = <-idleCh:
				case rawSp := <-spotifyCh:
					currentSpotify = rawSp
				case <-swayCh:
				default:
					break drainLoop
				}
			}
			time.Sleep(5 * time.Second)
			continue
		}

		log.Printf("[lived] connected to %s", *endpointFlag)
		readErrCh := make(chan error, 1)
		demandCh := make(chan bool, 4)

		go func(c *wsClient) {
			for {
				raw, err := c.ReadMessage()
				if err != nil {
					readErrCh <- err
					return
				}
				if string(raw) == "pong" {
					continue
				}
				var msg IncomingMessage
				if json.Unmarshal(raw, &msg) == nil {
					switch msg.Kind {
					case "demand":
						select {
						case demandCh <- msg.Active:
						default:
						}
					case "poke":
						snap := buildSnapshot(waylandIdle, currentSpotify)
						if snap.Online && snap.Desktop != nil && snap.Desktop.ScreenOn {
							go notifyPoke()
						}
					}
				}
			}
		}(ws)

		var lastDesktop DesktopState
		var lastStatus string
		var lastOnline bool
		visitorsActive := false

		sendSnap := func(force bool) error {
			if !visitorsActive {
				return nil
			}
			snap := buildSnapshot(waylandIdle, currentSpotify)
			if !force && snap.Desktop != nil &&
				*snap.Desktop == lastDesktop &&
				snap.Status == lastStatus &&
				snap.Online == lastOnline {
				return nil
			}
			if snap.Desktop != nil {
				lastDesktop = *snap.Desktop
			}
			lastStatus = snap.Status
			lastOnline = snap.Online

			b, err := json.Marshal(snap)
			if err != nil {
				return err
			}
			return ws.WriteText(b)
		}

		pingTicker := time.NewTicker(25 * time.Second)

		connAlive := true
		for connAlive {
			select {
			case err := <-readErrCh:
				log.Printf("[lived] ws closed: %v", err)
				connAlive = false
			case active := <-demandCh:
				visitorsActive = active
				if visitorsActive {
					if err := sendSnap(true); err != nil {
						connAlive = false
					}
				}
			case waylandIdle = <-idleCh:
				if err := sendSnap(false); err != nil {
					connAlive = false
				}
			case nextSp := <-spotifyCh:
				if !spotifyEqual(currentSpotify, nextSp) {
					currentSpotify = nextSp
					if err := sendSnap(true); err != nil {
						connAlive = false
					}
				}
			case <-swayCh:
				if !visitorsActive {
					continue
				}
				time.Sleep(60 * time.Millisecond)
			drainSway:
				for {
					select {
					case <-swayCh:
					default:
						break drainSway
					}
				}
				if err := sendSnap(false); err != nil {
					connAlive = false
				}
			case <-pingTicker.C:
				if err := ws.WriteText([]byte("ping")); err != nil {
					connAlive = false
				}
			}
		}

		pingTicker.Stop()
		ws.Close()
		time.Sleep(3 * time.Second)
	}
}
