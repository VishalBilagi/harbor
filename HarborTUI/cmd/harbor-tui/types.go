package main

import (
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"
)

type snapshotEnvelope struct {
	SchemaVersion int              `json:"schemaVersion"`
	GeneratedAt   time.Time        `json:"generatedAt"`
	Listeners     []listenerRecord `json:"listeners"`
}

type listenerRecord struct {
	Proto               string   `json:"proto"`
	Port                int      `json:"port"`
	BindAddress         string   `json:"bindAddress"`
	Family              string   `json:"family"`
	PID                 int      `json:"pid"`
	ProcessName         string   `json:"processName"`
	CommandLine         *string  `json:"commandLine"`
	Cwd                 *string  `json:"cwd"`
	CPUPercent          *float64 `json:"cpuPercent"`
	MemBytes            *uint64  `json:"memBytes"`
	RequiresAdminToKill *bool    `json:"requiresAdminToKill"`
}

func sortedListeners(listeners []listenerRecord) []listenerRecord {
	cloned := append([]listenerRecord(nil), listeners...)
	sort.Slice(cloned, func(i, j int) bool {
		left := cloned[i]
		right := cloned[j]

		if left.Port != right.Port {
			return left.Port < right.Port
		}

		if left.PID != right.PID {
			return left.PID < right.PID
		}

		if left.Family != right.Family {
			return left.Family < right.Family
		}

		return left.BindAddress < right.BindAddress
	})

	return cloned
}

func applyFilter(listeners []listenerRecord, query string) []listenerRecord {
	trimmed := strings.TrimSpace(strings.ToLower(query))
	if trimmed == "" {
		return append([]listenerRecord(nil), listeners...)
	}

	filtered := make([]listenerRecord, 0, len(listeners))
	for _, listener := range listeners {
		if matchesFilter(listener, trimmed) {
			filtered = append(filtered, listener)
		}
	}

	return filtered
}

func matchesFilter(listener listenerRecord, query string) bool {
	if strings.Contains(strings.ToLower(strconv.Itoa(listener.Port)), query) {
		return true
	}

	if strings.Contains(strings.ToLower(listener.ProcessName), query) {
		return true
	}

	if strings.Contains(strings.ToLower(derefString(listener.CommandLine)), query) {
		return true
	}

	if strings.Contains(strings.ToLower(derefString(listener.Cwd)), query) {
		return true
	}

	return false
}

func selectedKey(listener listenerRecord) string {
	return fmt.Sprintf("%d|%d|%s|%s", listener.Port, listener.PID, listener.Family, listener.BindAddress)
}

func listenerCommand(listener listenerRecord) string {
	value := strings.TrimSpace(derefString(listener.CommandLine))
	if value == "" {
		return "-"
	}
	return value
}

func listenerCwd(listener listenerRecord) string {
	value := strings.TrimSpace(derefString(listener.Cwd))
	if value == "" {
		return "-"
	}
	return value
}

func listenerFamily(listener listenerRecord) string {
	switch strings.ToLower(listener.Family) {
	case "ipv4":
		return "IPv4"
	case "ipv6":
		return "IPv6"
	default:
		if listener.Family == "" {
			return "-"
		}
		return listener.Family
	}
}

func listenerCPU(listener listenerRecord) string {
	if listener.CPUPercent == nil {
		return "-"
	}

	return fmt.Sprintf("%.1f%%", *listener.CPUPercent)
}

func listenerMemory(listener listenerRecord) string {
	if listener.MemBytes == nil {
		return "-"
	}

	return formatBytes(*listener.MemBytes)
}

func listenerAdminState(listener listenerRecord) string {
	if listener.RequiresAdminToKill == nil {
		return "unknown"
	}

	if *listener.RequiresAdminToKill {
		return "yes"
	}

	return "no"
}

func listenerRequiresAdmin(listener listenerRecord) bool {
	return listener.RequiresAdminToKill != nil && *listener.RequiresAdminToKill
}

func formatBytes(value uint64) string {
	const unit = 1024
	if value < unit {
		return fmt.Sprintf("%d B", value)
	}

	divisor := float64(unit)
	prefixes := []string{"KiB", "MiB", "GiB", "TiB"}
	index := 0
	for index < len(prefixes)-1 && float64(value) >= divisor*unit {
		divisor *= unit
		index++
	}

	return fmt.Sprintf("%.1f %s", float64(value)/divisor, prefixes[index])
}

func derefString(value *string) string {
	if value == nil {
		return ""
	}

	return *value
}

func runeLen(value string) int {
	return len([]rune(value))
}

func truncate(value string, width int) string {
	if width <= 0 {
		return ""
	}

	runes := []rune(value)
	if len(runes) <= width {
		return value
	}

	if width <= 3 {
		return string(runes[:width])
	}

	return string(runes[:width-3]) + "..."
}

func pad(value string, width int) string {
	trimmed := truncate(value, width)
	padding := width - runeLen(trimmed)
	if padding <= 0 {
		return trimmed
	}
	return trimmed + strings.Repeat(" ", padding)
}
