package main

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"time"
)

type claudeLine struct {
	Timestamp any `json:"timestamp"`
	Message   *struct {
		Model string `json:"model"`
		Usage *struct {
			InputTokens              int64 `json:"input_tokens"`
			OutputTokens             int64 `json:"output_tokens"`
			CacheReadInputTokens     int64 `json:"cache_read_input_tokens"`
			CacheCreationInputTokens int64 `json:"cache_creation_input_tokens"`
		} `json:"usage"`
	} `json:"message"`
}

func parseClaudeTime(raw any) time.Time {
	switch v := raw.(type) {
	case string:
		if t, err := time.Parse(time.RFC3339Nano, v); err == nil {
			return t
		}
		if t, err := time.Parse(time.RFC3339, v); err == nil {
			return t
		}
	case float64:
		return time.UnixMilli(int64(v))
	}
	return time.Now()
}

func scanClaude(homeDir string) ([]RawUsageEvent, error) {
	projectsDir := filepath.Join(homeDir, ".claude", "projects")
	if _, err := os.Stat(projectsDir); err != nil {
		return nil, nil
	}

	files, err := filepath.Glob(filepath.Join(projectsDir, "*", "*.jsonl"))
	if err != nil {
		return nil, err
	}

	var events []RawUsageEvent
	for _, file := range files {
		f, err := os.Open(file)
		if err != nil {
			continue
		}

		scanner := bufio.NewScanner(f)
		// Max line buffer 10MB in case of giant messages
		buf := make([]byte, 64*1024)
		scanner.Buffer(buf, 10*1024*1024)

		for scanner.Scan() {
			lineBytes := scanner.Bytes()
			// Fast check before JSON decode
			if len(lineBytes) == 0 || !containsUsage(lineBytes) {
				continue
			}

			var line claudeLine
			if err := json.Unmarshal(lineBytes, &line); err != nil {
				continue
			}

			if line.Message != nil && line.Message.Usage != nil {
				u := line.Message.Usage
				model := line.Message.Model
				if model == "" {
					model = "claude"
				}

				t := parseClaudeTime(line.Timestamp)
				input := u.InputTokens + u.CacheCreationInputTokens
				output := u.OutputTokens
				cacheRead := u.CacheReadInputTokens
				total := input + output + cacheRead

				events = append(events, RawUsageEvent{
					Tool:      "claude",
					Model:     model,
					Timestamp: t,
					Stats: TokenStats{
						Total:     total,
						Input:     input,
						Output:    output,
						CacheRead: cacheRead,
					},
				})
			}
		}
		f.Close()
	}

	return events, nil
}

func containsUsage(b []byte) bool {
	// Simple subslice check for `"usage"`
	target := []byte(`"usage"`)
	for i := 0; i+len(target) <= len(b); i++ {
		if b[i] == '"' && string(b[i:i+len(target)]) == `"usage"` {
			return true
		}
	}
	return false
}
