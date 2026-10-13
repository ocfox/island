package main

import (
	"database/sql"
	"os"
	"path/filepath"

	_ "modernc.org/sqlite"
)

// readVarint reads a protobuf unsigned varint from buf starting at offset.
func readVarint(buf []byte, offset int) (uint64, int, bool) {
	var res uint64
	var shift uint
	pos := offset
	for pos < len(buf) {
		b := buf[pos]
		pos++
		res |= uint64(b&0x7F) << shift
		shift += 7
		if (b & 0x80) == 0 {
			return res, pos, true
		}
	}
	return 0, offset, false
}

// parseProtoFields extracts wire fields into a map[fieldNumber][]bytes or varint values.
func parseProtoFields(buf []byte) (varints map[int]uint64, bytesFields map[int][]byte) {
	varints = make(map[int]uint64)
	bytesFields = make(map[int][]byte)

	pos := 0
	for pos < len(buf) {
		tag, next, ok := readVarint(buf, pos)
		if !ok {
			break
		}
		pos = next
		fieldNum := int(tag >> 3)
		wireType := int(tag & 7)

		switch wireType {
		case 0: // Varint
			val, nextVal, okVal := readVarint(buf, pos)
			if !okVal {
				return
			}
			pos = nextVal
			varints[fieldNum] = val
		case 2: // Length-delimited (submessage or string or bytes)
			lenVal, nextVal, okVal := readVarint(buf, pos)
			if !okVal {
				return
			}
			pos = nextVal
			end := pos + int(lenVal)
			if end > len(buf) {
				return
			}
			bytesFields[fieldNum] = buf[pos:end]
			pos = end
		default:
			// For unknown wire types, stop parsing to prevent misalignment
			return
		}
	}
	return
}

func scanAntigravity(homeDir string) ([]RawUsageEvent, error) {
	convDir := filepath.Join(homeDir, ".gemini", "antigravity-cli", "conversations")
	if _, err := os.Stat(convDir); err != nil {
		return nil, nil
	}

	files, err := filepath.Glob(filepath.Join(convDir, "*.db"))
	if err != nil {
		return nil, err
	}

	var events []RawUsageEvent

	for _, file := range files {
		fi, err := os.Stat(file)
		if err != nil {
			continue
		}
		modTime := fi.ModTime()

		db, err := sql.Open("sqlite", "file:"+file+"?mode=ro")
		if err != nil {
			continue
		}

		rows, err := db.Query("SELECT data FROM gen_metadata")
		if err != nil {
			db.Close()
			continue
		}

		for rows.Next() {
			var blob []byte
			if err := rows.Scan(&blob); err != nil {
				continue
			}

			_, rootBytes := parseProtoFields(blob)
			chatModelBlob, hasChatModel := rootBytes[1]
			if !hasChatModel {
				continue
			}

			_, chatModelBytes := parseProtoFields(chatModelBlob)
			usageBlob, hasUsage := chatModelBytes[4]
			if !hasUsage {
				continue
			}

			usageVarints, _ := parseProtoFields(usageBlob)
			input := int64(usageVarints[1] + usageVarints[2])
			cacheRead := int64(usageVarints[5])
			output := int64(usageVarints[9])
			reasoning := int64(usageVarints[10])
			total := input + output + cacheRead + reasoning

			if total == 0 {
				continue
			}

			model := "gemini"
			if m, ok := chatModelBytes[19]; ok && len(m) > 0 {
				model = string(m)
			} else if m, ok := chatModelBytes[21]; ok && len(m) > 0 {
				model = string(m)
			}

			events = append(events, RawUsageEvent{
				Tool:      "antigravity",
				Model:     model,
				Timestamp: modTime,
				Stats: TokenStats{
					Total:     total,
					Input:     input,
					Output:    output,
					CacheRead: cacheRead,
					Reasoning: reasoning,
				},
			})
		}

		rows.Close()
		db.Close()
	}

	return events, nil
}
