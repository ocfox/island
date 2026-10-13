package main

import (
	"bufio"
	"encoding/json"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type codexLine struct {
	Timestamp any    `json:"timestamp"`
	Type      string `json:"type"`
	Payload   *struct {
		Type  string `json:"type"`
		Model string `json:"model"`
		Info  *struct {
			LastTokenUsage *struct {
				InputTokens           int64 `json:"input_tokens"`
				OutputTokens          int64 `json:"output_tokens"`
				CachedInputTokens     int64 `json:"cached_input_tokens"`
				ReasoningOutputTokens int64 `json:"reasoning_output_tokens"`
			} `json:"last_token_usage"`
		} `json:"info"`
	} `json:"payload"`
}

func parseCodexTime(raw any) time.Time {
	switch v := raw.(type) {
	case float64:
		// Could be seconds or millis
		iv := int64(v)
		if iv > 1e11 {
			return time.UnixMilli(iv)
		}
		return time.Unix(iv, 0)
	case string:
		if t, err := time.Parse(time.RFC3339Nano, v); err == nil {
			return t
		}
		if t, err := time.Parse(time.RFC3339, v); err == nil {
			return t
		}
	}
	return time.Now()
}

func scanCodex(homeDir string) ([]RawUsageEvent, error) {
	sessionsDir := filepath.Join(homeDir, ".codex", "sessions")
	if _, err := os.Stat(sessionsDir); err != nil {
		return nil, nil
	}

	var events []RawUsageEvent

	err := filepath.WalkDir(sessionsDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() || !strings.HasSuffix(d.Name(), ".jsonl") {
			return nil
		}

		f, err := os.Open(path)
		if err != nil {
			return nil
		}
		defer f.Close()

		currentModel := "gpt-5"

		scanner := bufio.NewScanner(f)
		buf := make([]byte, 64*1024)
		scanner.Buffer(buf, 10*1024*1024)

		for scanner.Scan() {
			lineBytes := scanner.Bytes()
			if len(lineBytes) == 0 {
				continue
			}

			var line codexLine
			if err := json.Unmarshal(lineBytes, &line); err != nil {
				continue
			}

			if line.Payload != nil {
				if line.Payload.Model != "" {
					currentModel = line.Payload.Model
				}

				if line.Type == "event_msg" && line.Payload.Type == "token_count" && line.Payload.Info != nil {
					if u := line.Payload.Info.LastTokenUsage; u != nil {
						t := parseCodexTime(line.Timestamp)
						input := u.InputTokens
						output := u.OutputTokens
						cacheRead := u.CachedInputTokens
						reasoning := u.ReasoningOutputTokens
						total := input + output + cacheRead + reasoning

						if total > 0 {
							events = append(events, RawUsageEvent{
								Tool:      "codex",
								Model:     currentModel,
								Timestamp: t,
								Stats: TokenStats{
									Total:     total,
									Input:     input,
									Output:    output,
									CacheRead: cacheRead,
									Reasoning: reasoning,
								},
							})
						}
					}
				}
			}
		}
		return nil
	})

	return events, err
}
