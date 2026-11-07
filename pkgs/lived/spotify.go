package main

import (
	"bufio"
	"context"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

const playerctlFormat = "{{status}}\t{{mpris:trackid}}\t{{title}}\t{{artist}}\t{{album}}\t{{mpris:artUrl}}\t{{mpris:length}}\t{{position}}"

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

func parsePlayerctlLine(line string) *SpotifyData {
	parts := strings.Split(line, "\t")
	if len(parts) < 8 {
		return nil
	}
	status := strings.TrimSpace(parts[0])
	if status != "Playing" {
		return nil
	}
	title := strings.TrimSpace(parts[2])
	if title == "" {
		return nil
	}
	artist := strings.TrimSpace(parts[3])
	album := strings.TrimSpace(parts[4])
	trackID := extractSpotifyTrackID(parts[1])
	artURL := normalizeSpotifyArt(parts[5])

	lengthUs, _ := strconv.ParseInt(strings.TrimSpace(parts[6]), 10, 64)
	posUs, _ := strconv.ParseInt(strings.TrimSpace(parts[7]), 10, 64)

	nowMs := time.Now().UnixMilli()
	posMs := posUs / 1000
	durMs := lengthUs / 1000
	if durMs < posMs {
		durMs = posMs
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

func querySpotifyOnce() *SpotifyData {
	ctx, cancel := context.WithTimeout(context.Background(), 1500*time.Millisecond)
	defer cancel()
	out, err := exec.CommandContext(ctx, "playerctl", "--player=spotify", "metadata", "--format", playerctlFormat).Output()
	if err != nil {
		return nil
	}
	line := strings.TrimRight(string(out), "\r\n")
	return parsePlayerctlLine(line)
}

func watchSpotify(ch chan<- *SpotifyData) {
	for {
		cmd := exec.Command("playerctl", "--player=spotify", "--follow", "metadata", "--format", playerctlFormat)
		stdout, err := cmd.StdoutPipe()
		if err != nil {
			time.Sleep(5 * time.Second)
			continue
		}
		if err := cmd.Start(); err != nil {
			time.Sleep(5 * time.Second)
			continue
		}

		scanner := bufio.NewScanner(stdout)
		for scanner.Scan() {
			line := scanner.Text()
			ch <- parsePlayerctlLine(line)
		}

		_ = cmd.Wait()
		ch <- nil
		time.Sleep(3 * time.Second)
	}
}
