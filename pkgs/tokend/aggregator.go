package main

import (
	"encoding/json"
	"sort"
	"strings"
	"time"
)

func aggregate(events []RawUsageEvent) Payload {
	now := time.Now()
	todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	weekStart := now.AddDate(0, 0, -7)
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
	thirtyDaysAgo := todayStart.AddDate(0, 0, -29)

	var summary SummaryStats
	byTool := map[string]ToolStats{
		"claude":      {},
		"codex":       {},
		"antigravity": {},
		"opencode":    {},
	}
	byModel := make(map[string]TokenStats)
	dailyMap := make(map[string]*TokenStats)

	// Pre-fill dailyMap for the last 30 days with zeros so the series is continuous
	for i := 0; i < 30; i++ {
		d := thirtyDaysAgo.AddDate(0, 0, i).Format("2006-01-02")
		dailyMap[d] = &TokenStats{}
	}

	for _, ev := range events {
		st := ev.Stats
		t := ev.Timestamp

		// All-time
		summary.AllTime.Add(st)

		// This Month
		if !t.Before(monthStart) {
			summary.ThisMonth.Add(st)
		}

		// This Week (last 7 days)
		if !t.Before(weekStart) {
			summary.ThisWeek.Add(st)
		}

		// Today
		isToday := !t.Before(todayStart)
		if isToday {
			summary.Today.Add(st)
		}

		// By Tool
		toolEntry := byTool[ev.Tool]
		toolEntry.Total.Add(st)
		if isToday {
			toolEntry.Today.Add(st)
		}
		byTool[ev.Tool] = toolEntry

		// By Model
		modelName := cleanModelName(ev.Model)
		modelEntry := byModel[modelName]
		modelEntry.Add(st)
		byModel[modelName] = modelEntry

		// Daily (only for the last 30 days)
		dayKey := t.Format("2006-01-02")
		if dayStats, ok := dailyMap[dayKey]; ok {
			dayStats.Add(st)
		}
	}

	// Convert daily map to sorted slice
	var dailyList []DailyStats
	for dayKey, stats := range dailyMap {
		dailyList = append(dailyList, DailyStats{
			Date:       dayKey,
			TokenStats: *stats,
		})
	}
	sort.Slice(dailyList, func(i, j int) bool {
		return dailyList[i].Date < dailyList[j].Date
	})

	return Payload{
		UpdatedAt: now.UnixMilli(),
		Summary:   summary,
		ByTool:    byTool,
		ByModel:   byModel,
		Daily:     dailyList,
	}
}

func cleanModelName(raw string) string {
	raw = strings.TrimSpace(raw)
	if strings.HasPrefix(raw, "{") && strings.HasSuffix(raw, "}") {
		var obj struct {
			ID string `json:"id"`
		}
		if err := json.Unmarshal([]byte(raw), &obj); err == nil && obj.ID != "" {
			return obj.ID
		}
	}
	return raw
}
