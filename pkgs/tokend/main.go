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
		file = os.Getenv("TOKEND_SECRET_FILE")
	}
	if file != "" {
		data, err := os.ReadFile(file)
		if err == nil {
			return strings.TrimSpace(string(data))
		}
		log.Printf("warning: failed to read secret file %s: %v", file, err)
	}
	return os.Getenv("TOKEND_SECRET")
}

func runCollect(homeDir string) (Payload, error) {
	var allEvents []RawUsageEvent

	// 1. OpenCode
	opencodeEvents, err := scanOpenCode(homeDir)
	if err != nil {
		log.Printf("[opencode] scan error: %v", err)
	} else {
		allEvents = append(allEvents, opencodeEvents...)
	}

	// 2. Claude Code
	claudeEvents, err := scanClaude(homeDir)
	if err != nil {
		log.Printf("[claude] scan error: %v", err)
	} else {
		allEvents = append(allEvents, claudeEvents...)
	}

	// 3. Codex CLI
	codexEvents, err := scanCodex(homeDir)
	if err != nil {
		log.Printf("[codex] scan error: %v", err)
	} else {
		allEvents = append(allEvents, codexEvents...)
	}

	// 4. Antigravity CLI
	antigravityEvents, err := scanAntigravity(homeDir)
	if err != nil {
		log.Printf("[antigravity] scan error: %v", err)
	} else {
		allEvents = append(allEvents, antigravityEvents...)
	}

	payload := aggregate(allEvents)
	return payload, nil
}

func main() {
	endpointFlag := flag.String("endpoint", getEnv("TOKEND_ENDPOINT", ""), "Destination HTTP endpoint (e.g. https://s4r.in/api/tokens)")
	secretFlag := flag.String("secret", "", "Bearer secret for authentication")
	secretFileFlag := flag.String("secret-file", "", "Path to file containing Bearer secret")
	intervalFlag := flag.Int("interval", 300, "Collection interval in seconds")
	onceFlag := flag.Bool("once", false, "Collect and push once, then exit")
	printFlag := flag.Bool("print", false, "Print JSON payload to stdout and exit without pushing")
	flag.Parse()

	if envInterval := os.Getenv("TOKEND_INTERVAL_SECONDS"); envInterval != "" {
		if iv, err := strconv.Atoi(envInterval); err == nil && iv > 0 {
			*intervalFlag = iv
		}
	}

	homeDir, err := os.UserHomeDir()
	if err != nil {
		log.Fatalf("failed to get user home directory: %v", err)
	}

	secret := readSecret(*secretFlag, *secretFileFlag)

	doTick := func() {
		start := time.Now()
		payload, err := runCollect(homeDir)
		if err != nil {
			log.Printf("collection failed: %v", err)
			return
		}
		duration := time.Since(start)

		if *printFlag {
			data, _ := json.MarshalIndent(payload, "", "  ")
			fmt.Println(string(data))
			return
		}

		if *endpointFlag == "" {
			log.Printf("collected in %v: total=%d (today=%d), but no endpoint configured. Use -endpoint or TOKEND_ENDPOINT",
				duration, payload.Summary.AllTime.Total, payload.Summary.Today.Total)
			return
		}

		if err := pushPayload(*endpointFlag, secret, payload); err != nil {
			log.Printf("push to %s failed: %v", *endpointFlag, err)
		} else {
			log.Printf("successfully pushed in %v (today: %d, all_time: %d)",
				duration, payload.Summary.Today.Total, payload.Summary.AllTime.Total)
		}
	}

	doTick()
	if *onceFlag || *printFlag {
		return
	}

	ticker := time.NewTicker(time.Duration(*intervalFlag) * time.Second)
	defer ticker.Stop()

	log.Printf("tokend started, running every %d seconds...", *intervalFlag)
	for range ticker.C {
		doTick()
	}
}
