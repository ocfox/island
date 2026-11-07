package main

import (
	"context"
	"strings"
	"time"

	"github.com/godbus/dbus/v5"
)

const (
	spotifyBusName    = "org.mpris.MediaPlayer2.spotify"
	mprisObjectPath   = dbus.ObjectPath("/org/mpris/MediaPlayer2")
	mprisPlayerIface  = "org.mpris.MediaPlayer2.Player"
	dbusPropsIface    = "org.freedesktop.DBus.Properties"
	dbusPropsGetAll   = "org.freedesktop.DBus.Properties.GetAll"
	dbusPropsGet      = "org.freedesktop.DBus.Properties.Get"
	dbusGetNameOwner  = "org.freedesktop.DBus.GetNameOwner"
	sigNameOwnerChg   = "org.freedesktop.DBus.NameOwnerChanged"
	sigPropsChanged   = "org.freedesktop.DBus.Properties.PropertiesChanged"
	sigMprisSeeked    = "org.mpris.MediaPlayer2.Player.Seeked"
)

func extractSpotifyTrackID(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	if idx := strings.LastIndex(raw, "/"); idx != -1 {
		raw = raw[idx+1:]
	}
	if idx := strings.LastIndex(raw, ":"); idx != -1 {
		raw = raw[idx+1:]
	}
	if raw == "notrack" || raw == "ad" {
		return ""
	}
	return raw
}

func normalizeSpotifyArt(url string) string {
	url = strings.TrimSpace(url)
	if strings.HasPrefix(url, "https://open.spotify.com/image/") {
		return "https://i.scdn.co/image/" + strings.TrimPrefix(url, "https://open.spotify.com/image/")
	}
	return url
}

func variantString(v dbus.Variant) string {
	switch val := v.Value().(type) {
	case string:
		return val
	case dbus.ObjectPath:
		return string(val)
	default:
		return ""
	}
}

func variantArtist(v dbus.Variant) string {
	switch val := v.Value().(type) {
	case []string:
		return strings.Join(val, ", ")
	case string:
		return val
	default:
		return ""
	}
}

func variantMicros(v dbus.Variant) (int64, bool) {
	switch val := v.Value().(type) {
	case int64:
		return val, true
	case uint64:
		return int64(val), true
	case int32:
		return int64(val), true
	case uint32:
		return int64(val), true
	case float64:
		return int64(val), true
	default:
		return 0, false
	}
}

func extractMetaMap(v dbus.Variant) map[string]dbus.Variant {
	if m, ok := v.Value().(map[string]dbus.Variant); ok {
		return m
	}
	return nil
}

func buildSpotifyData(status string, meta map[string]dbus.Variant, posUs int64) *SpotifyData {
	if status != "Playing" || len(meta) == 0 {
		return nil
	}
	title := strings.TrimSpace(variantString(meta["xesam:title"]))
	if title == "" {
		return nil
	}
	artist := strings.TrimSpace(variantArtist(meta["xesam:artist"]))
	album := strings.TrimSpace(variantString(meta["xesam:album"]))
	trackID := extractSpotifyTrackID(variantString(meta["mpris:trackid"]))
	artURL := normalizeSpotifyArt(variantString(meta["mpris:artUrl"]))
	lengthUs, _ := variantMicros(meta["mpris:length"])

	nowMs := time.Now().UnixMilli()
	posMs := posUs / 1000
	durMs := lengthUs / 1000
	if posMs < 0 {
		posMs = 0
	}
	if durMs > 0 && posMs > durMs {
		posMs = 0
	}
	startMs := nowMs - posMs
	endMs := startMs + durMs

	return &SpotifyData{
		Song:        title,
		Artist:      artist,
		Album:       album,
		AlbumArtURL: artURL,
		TrackID:     trackID,
		Timestamps: Timestamps{
			Start: startMs,
			End:   endMs,
		},
	}
}

func sameTrack(a, b *SpotifyData) bool {
	if a == nil || b == nil {
		return false
	}
	if a.TrackID != "" && b.TrackID != "" {
		return a.TrackID == b.TrackID
	}
	return a.Song == b.Song && a.Artist == b.Artist
}

func spotifyEqual(a, b *SpotifyData) bool {
	if a == nil && b == nil {
		return true
	}
	if a == nil || b == nil {
		return false
	}
	return a.TrackID == b.TrackID &&
		a.Song == b.Song &&
		a.Artist == b.Artist &&
		a.AlbumArtURL == b.AlbumArtURL &&
		a.Timestamps.Start == b.Timestamps.Start &&
		a.Timestamps.End == b.Timestamps.End
}

func getSpotifyOwner(conn *dbus.Conn) string {
	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
	defer cancel()
	var owner string
	err := conn.BusObject().CallWithContext(ctx, dbusGetNameOwner, 0, spotifyBusName).Store(&owner)
	if err != nil {
		return ""
	}
	return owner
}

func syncFromSpotify(conn *dbus.Conn) (status string, meta map[string]dbus.Variant, posUs int64, ok bool) {
	ctx, cancel := context.WithTimeout(context.Background(), 1500*time.Millisecond)
	defer cancel()
	obj := conn.Object(spotifyBusName, mprisObjectPath)
	var props map[string]dbus.Variant
	if err := obj.CallWithContext(ctx, dbusPropsGetAll, 0, mprisPlayerIface).Store(&props); err != nil {
		return "", nil, 0, false
	}
	status = strings.TrimSpace(variantString(props["PlaybackStatus"]))
	meta = extractMetaMap(props["Metadata"])
	posUs, _ = variantMicros(props["Position"])
	return status, meta, posUs, true
}

func queryPositionDBus(conn *dbus.Conn) int64 {
	ctx, cancel := context.WithTimeout(context.Background(), 800*time.Millisecond)
	defer cancel()
	obj := conn.Object(spotifyBusName, mprisObjectPath)
	var v dbus.Variant
	if err := obj.CallWithContext(ctx, dbusPropsGet, 0, mprisPlayerIface, "Position").Store(&v); err != nil {
		return 0
	}
	posUs, _ := variantMicros(v)
	return posUs
}

func querySpotifyOnce() *SpotifyData {
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		return nil
	}
	defer conn.Close()

	status, meta, posUs, ok := syncFromSpotify(conn)
	if !ok {
		return nil
	}
	return buildSpotifyData(status, meta, posUs)
}

func applySeek(cur *SpotifyData, posUs int64) *SpotifyData {
	if cur == nil {
		return nil
	}
	durMs := cur.Timestamps.End - cur.Timestamps.Start
	posMs := posUs / 1000
	if posMs < 0 {
		posMs = 0
	}
	if durMs > 0 && posMs > durMs {
		posMs = durMs
	}
	nowMs := time.Now().UnixMilli()
	updated := *cur
	updated.Timestamps = Timestamps{
		Start: nowMs - posMs,
		End:   nowMs - posMs + durMs,
	}
	return &updated
}

func abs64(x int64) int64 {
	if x < 0 {
		return -x
	}
	return x
}

func watchSpotify(ch chan<- *SpotifyData) {
	for {
		conn, err := dbus.ConnectSessionBus()
		if err != nil {
			time.Sleep(5 * time.Second)
			continue
		}

		_ = conn.AddMatchSignal(
			dbus.WithMatchObjectPath(mprisObjectPath),
			dbus.WithMatchInterface(dbusPropsIface),
			dbus.WithMatchMember("PropertiesChanged"),
		)
		_ = conn.AddMatchSignal(
			dbus.WithMatchObjectPath(mprisObjectPath),
			dbus.WithMatchInterface(mprisPlayerIface),
			dbus.WithMatchMember("Seeked"),
		)
		_ = conn.AddMatchSignal(
			dbus.WithMatchSender("org.freedesktop.DBus"),
			dbus.WithMatchInterface("org.freedesktop.DBus"),
			dbus.WithMatchMember("NameOwnerChanged"),
			dbus.WithMatchArg(0, spotifyBusName),
		)

		sigCh := make(chan *dbus.Signal, 32)
		conn.Signal(sigCh)

		spotifyOwner := getSpotifyOwner(conn)
		var status string
		var meta map[string]dbus.Variant
		var last *SpotifyData

		if spotifyOwner != "" {
			if s, m, posUs, ok := syncFromSpotify(conn); ok {
				status = s
				meta = m
				last = buildSpotifyData(status, meta, posUs)
				ch <- last
			}
		}

		for sig := range sigCh {
			if sig == nil {
				break
			}

			switch sig.Name {
			case sigNameOwnerChg:
				if len(sig.Body) < 3 {
					continue
				}
				name, _ := sig.Body[0].(string)
				newOwner, _ := sig.Body[2].(string)
				if name != spotifyBusName {
					continue
				}
				spotifyOwner = newOwner
				if spotifyOwner == "" {
					status = ""
					meta = nil
					if last != nil {
						last = nil
						ch <- nil
					}
				} else if s, m, posUs, ok := syncFromSpotify(conn); ok {
					status = s
					meta = m
					last = buildSpotifyData(status, meta, posUs)
					ch <- last
				}

			case sigMprisSeeked:
				if spotifyOwner == "" || sig.Sender != spotifyOwner || len(sig.Body) < 1 {
					continue
				}
				posUs, ok := variantMicros(dbus.MakeVariant(sig.Body[0]))
				if !ok {
					continue
				}
				if last != nil {
					last = applySeek(last, posUs)
					ch <- last
				} else if status == "Playing" && len(meta) > 0 {
					last = buildSpotifyData(status, meta, posUs)
					ch <- last
				}

			case sigPropsChanged:
				if spotifyOwner == "" || sig.Sender != spotifyOwner || len(sig.Body) < 2 {
					continue
				}
				iface, _ := sig.Body[0].(string)
				if iface != mprisPlayerIface {
					continue
				}
				changed, ok := sig.Body[1].(map[string]dbus.Variant)
				if !ok {
					continue
				}

				if status == "" && len(meta) == 0 {
					if s, m, posUs, ok := syncFromSpotify(conn); ok {
						status = s
						meta = m
						last = buildSpotifyData(status, meta, posUs)
						ch <- last
					}
					continue
				}

				if stVar, hasSt := changed["PlaybackStatus"]; hasSt {
					status = strings.TrimSpace(variantString(stVar))
				}
				if metaVar, hasMeta := changed["Metadata"]; hasMeta {
					if m := extractMetaMap(metaVar); m != nil {
						meta = m
					}
				}

				if status != "Playing" {
					if last != nil {
						last = nil
						ch <- nil
					}
					continue
				}

				if len(meta) == 0 {
					if s, m, posUs, ok := syncFromSpotify(conn); ok {
						status = s
						meta = m
						last = buildSpotifyData(status, meta, posUs)
						ch <- last
					}
					continue
				}

				probe := buildSpotifyData(status, meta, 0)
				if probe == nil {
					if last != nil {
						last = nil
						ch <- nil
					}
					continue
				}

				if last != nil && sameTrack(last, probe) {
					// Same track still playing: keep original timestamps unless Position jumped significantly
					probe.Timestamps = last.Timestamps
					if posVar, hasPos := changed["Position"]; hasPos {
						if posUs, ok := variantMicros(posVar); ok {
							expectedMs := time.Now().UnixMilli() - last.Timestamps.Start
							if abs64(posUs/1000-expectedMs) > 1500 {
								probe = applySeek(probe, posUs)
							}
						}
					}
					last = probe
					ch <- last
					continue
				}

				// Either resumed from pause (last == nil) or switched directly to a new track
				var posUs int64
				if last == nil {
					if posVar, hasPos := changed["Position"]; hasPos {
						posUs, _ = variantMicros(posVar)
					} else {
						posUs = queryPositionDBus(conn)
					}
				} else {
					// Switched directly from Track A to Track B -> starts at 0:00
					posUs = 0
				}
				last = buildSpotifyData(status, meta, posUs)
				ch <- last
			}
		}

		_ = conn.Close()
		ch <- nil
		time.Sleep(3 * time.Second)
	}
}
