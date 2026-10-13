package main

import (
	"database/sql"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"
)

func scanOpenCode(homeDir string) ([]RawUsageEvent, error) {
	dbPath := filepath.Join(homeDir, ".local", "share", "opencode", "opencode.db")
	if _, err := os.Stat(dbPath); err != nil {
		return nil, nil // not found, skip gracefully
	}

	// Open in read-only mode to prevent locking or write collisions
	db, err := sql.Open("sqlite", "file:"+dbPath+"?mode=ro")
	if err != nil {
		return nil, err
	}
	defer db.Close()

	rows, err := db.Query(`
		SELECT 
			COALESCE(model, 'unknown'),
			time_updated,
			tokens_input,
			tokens_output,
			tokens_reasoning,
			tokens_cache_read
		FROM session
		WHERE (tokens_input > 0 OR tokens_output > 0 OR tokens_cache_read > 0)
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var events []RawUsageEvent
	for rows.Next() {
		var model string
		var timeMs int64
		var input, output, reasoning, cacheRead int64

		if err := rows.Scan(&model, &timeMs, &input, &output, &reasoning, &cacheRead); err != nil {
			continue
		}

		t := time.UnixMilli(timeMs)
		total := input + output + cacheRead + reasoning

		events = append(events, RawUsageEvent{
			Tool:      "opencode",
			Model:     model,
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

	return events, nil
}
