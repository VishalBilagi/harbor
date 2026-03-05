package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

func TestDataSourceFallsBackFromWatchStreamToPolling(t *testing.T) {
	harborBin := writeHarborStub(t, `#!/bin/sh
if [ "$1" = "watch" ]; then
  echo '{"schemaVersion":1,"generatedAt":"2026-03-05T15:00:00Z","listeners":[{"proto":"tcp","port":3000,"bindAddress":"127.0.0.1","family":"ipv4","pid":100,"processName":"watch","commandLine":"node watch.js","cwd":"/tmp/watch","cpuPercent":null,"memBytes":null,"requiresAdminToKill":false}]}'
  echo 'watch stream exited' 1>&2
  exit 1
fi

if [ "$1" = "list" ]; then
  echo '{"schemaVersion":1,"generatedAt":"2026-03-05T15:00:01Z","listeners":[{"proto":"tcp","port":5432,"bindAddress":"127.0.0.1","family":"ipv4","pid":200,"processName":"poll","commandLine":"postgres","cwd":"/tmp/db","cpuPercent":null,"memBytes":null,"requiresAdminToKill":false}]}'
  exit 0
fi

echo 'unexpected command' 1>&2
exit 2
`)

	events := make(chan tea.Msg, 256)
	source := newHarborDataSource(harborBin, 50*time.Millisecond, events)
	source.Start()
	defer source.Stop()

	deadline := time.After(3 * time.Second)
	sawStreamingMode := false
	sawPollingMode := false
	snapshotCount := 0

	for !(sawStreamingMode && sawPollingMode && snapshotCount >= 2) {
		select {
		case msg := <-events:
			switch typed := msg.(type) {
			case backendModeMsg:
				if typed.Mode == dataModeStreaming {
					sawStreamingMode = true
				}
				if typed.Mode == dataModePolling {
					sawPollingMode = true
				}
			case backendSnapshotMsg:
				snapshotCount++
			}
		case <-deadline:
			t.Fatalf("timed out waiting for stream+poll flow (stream=%v poll=%v snapshots=%d)", sawStreamingMode, sawPollingMode, snapshotCount)
		}
	}
}

func writeHarborStub(t *testing.T, script string) string {
	t.Helper()

	path := filepath.Join(t.TempDir(), "harbor-stub")
	if err := os.WriteFile(path, []byte(script), 0o755); err != nil {
		t.Fatalf("write stub: %v", err)
	}

	return path
}
