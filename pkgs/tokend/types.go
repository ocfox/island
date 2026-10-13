package main

import "time"

type TokenStats struct {
	Total     int64 `json:"total"`
	Input     int64 `json:"input"`
	Output    int64 `json:"output"`
	CacheRead int64 `json:"cache_read"`
	Reasoning int64 `json:"reasoning,omitempty"`
}

func (s *TokenStats) Add(other TokenStats) {
	s.Total += other.Total
	s.Input += other.Input
	s.Output += other.Output
	s.CacheRead += other.CacheRead
	s.Reasoning += other.Reasoning
}

type ToolStats struct {
	Total TokenStats `json:"total"`
	Today TokenStats `json:"today"`
}

type DailyStats struct {
	Date string `json:"date"` // YYYY-MM-DD
	TokenStats
}

type SummaryStats struct {
	Today     TokenStats `json:"today"`
	ThisWeek  TokenStats `json:"this_week"`
	ThisMonth TokenStats `json:"this_month"`
	AllTime   TokenStats `json:"all_time"`
}

type Payload struct {
	UpdatedAt int64                 `json:"updated_at"` // Unix epoch milliseconds
	Summary   SummaryStats          `json:"summary"`
	ByTool    map[string]ToolStats  `json:"by_tool"`
	ByModel   map[string]TokenStats `json:"by_model"`
	Daily     []DailyStats          `json:"daily"`
}

type RawUsageEvent struct {
	Tool      string
	Model     string
	Timestamp time.Time
	Stats     TokenStats
}
