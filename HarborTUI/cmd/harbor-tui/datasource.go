package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

type dataMode string

const (
	dataModeConnecting dataMode = "connecting"
	dataModeStreaming  dataMode = "stream"
	dataModePolling    dataMode = "polling"
)

type backendModeMsg struct {
	Mode dataMode
}

type backendStatusMsg struct {
	Text    string
	IsError bool
}

type backendSnapshotMsg struct {
	Snapshot snapshotEnvelope
}

type backendClosedMsg struct{}

type harborDataSource struct {
	harborBin string
	interval  time.Duration
	events    chan<- tea.Msg

	reconnectCh chan struct{}
	stopCh      chan struct{}
	doneCh      chan struct{}

	startOnce sync.Once
	stopOnce  sync.Once
}

func newHarborDataSource(harborBin string, interval time.Duration, events chan<- tea.Msg) *harborDataSource {
	return &harborDataSource{
		harborBin:   harborBin,
		interval:    interval,
		events:      events,
		reconnectCh: make(chan struct{}, 1),
		stopCh:      make(chan struct{}),
		doneCh:      make(chan struct{}),
	}
}

func (source *harborDataSource) Start() {
	source.startOnce.Do(func() {
		go source.run()
	})
}

func (source *harborDataSource) Stop() {
	source.stopOnce.Do(func() {
		close(source.stopCh)
		<-source.doneCh
	})
}

func (source *harborDataSource) RequestReconnect() {
	select {
	case source.reconnectCh <- struct{}{}:
	default:
	}
}

type loopResult int

const (
	loopStopped loopResult = iota
	loopReconnect
	loopFallbackToPolling
)

func (source *harborDataSource) run() {
	defer close(source.doneCh)
	defer source.emit(backendClosedMsg{})

	source.emit(backendModeMsg{Mode: dataModeConnecting})
	source.emit(backendStatusMsg{Text: "Connecting to harbor watch stream..."})

	for {
		streamResult := source.runStreamMode()
		switch streamResult {
		case loopStopped:
			return
		case loopReconnect:
			source.emit(backendModeMsg{Mode: dataModeConnecting})
			source.emit(backendStatusMsg{Text: "Reconnecting to harbor watch stream..."})
			continue
		case loopFallbackToPolling:
			pollResult := source.runPollingMode()
			switch pollResult {
			case loopStopped:
				return
			case loopReconnect:
				source.emit(backendModeMsg{Mode: dataModeConnecting})
				source.emit(backendStatusMsg{Text: "Retrying watch stream..."})
				continue
			default:
				continue
			}
		}
	}
}

func (source *harborDataSource) runStreamMode() loopResult {
	args := []string{
		"watch",
		"--interval",
		strconv.FormatFloat(source.interval.Seconds(), 'f', -1, 64),
		"--jsonl",
	}
	cmd := exec.Command(source.harborBin, args...)

	stdoutPipe, err := cmd.StdoutPipe()
	if err != nil {
		source.emit(backendStatusMsg{Text: fmt.Sprintf("Unable to read harbor watch output: %v", err), IsError: true})
		return loopFallbackToPolling
	}

	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Start(); err != nil {
		source.emit(backendStatusMsg{Text: fmt.Sprintf("Failed to start harbor watch --jsonl: %v", err), IsError: true})
		return loopFallbackToPolling
	}

	source.emit(backendModeMsg{Mode: dataModeStreaming})
	source.emit(backendStatusMsg{Text: "Streaming snapshots from harbor watch --jsonl"})

	type streamEvent struct {
		line string
		done bool
		err  error
	}

	streamEvents := make(chan streamEvent, 1)
	stopScanner := make(chan struct{})
	defer close(stopScanner)

	go func() {
		defer close(streamEvents)

		scanner := bufio.NewScanner(stdoutPipe)
		scanner.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)

		push := func(event streamEvent) bool {
			select {
			case streamEvents <- event:
				return true
			case <-stopScanner:
				return false
			}
		}

		for scanner.Scan() {
			if !push(streamEvent{line: scanner.Text()}) {
				return
			}
		}
		_ = push(streamEvent{done: true, err: scanner.Err()})
	}()

	for {
		select {
		case <-source.stopCh:
			_ = cmd.Process.Kill()
			_ = cmd.Wait()
			return loopStopped
		case <-source.reconnectCh:
			_ = cmd.Process.Kill()
			_ = cmd.Wait()
			return loopReconnect
		case event, ok := <-streamEvents:
			if !ok {
				_ = cmd.Wait()
				source.emit(backendStatusMsg{Text: "harbor watch stream closed unexpectedly; switching to polling fallback", IsError: true})
				return loopFallbackToPolling
			}

			if event.done {
				waitErr := cmd.Wait()
				if event.err != nil {
					source.emit(backendStatusMsg{Text: fmt.Sprintf("Error reading harbor watch stream: %v", event.err), IsError: true})
				}

				if waitErr != nil {
					errorText := formatExecError(waitErr, stderr.String())
					source.emit(backendStatusMsg{Text: fmt.Sprintf("harbor watch exited: %s", errorText), IsError: true})
				}

				source.emit(backendStatusMsg{Text: "Switching to harbor list --json polling fallback", IsError: true})
				return loopFallbackToPolling
			}

			line := strings.TrimSpace(event.line)
			if line == "" {
				continue
			}

			var snapshot snapshotEnvelope
			if err := json.Unmarshal([]byte(line), &snapshot); err != nil {
				source.emit(backendStatusMsg{Text: fmt.Sprintf("Invalid JSONL snapshot from watch stream: %v", err), IsError: true})
				continue
			}

			source.emit(backendSnapshotMsg{Snapshot: snapshot})
		}
	}
}

func (source *harborDataSource) runPollingMode() loopResult {
	source.emit(backendModeMsg{Mode: dataModePolling})
	source.emit(backendStatusMsg{Text: "Polling snapshots via harbor list --json"})

	source.pollOnce()

	ticker := time.NewTicker(source.interval)
	defer ticker.Stop()

	for {
		select {
		case <-source.stopCh:
			return loopStopped
		case <-source.reconnectCh:
			return loopReconnect
		case <-ticker.C:
			source.pollOnce()
		}
	}
}

func (source *harborDataSource) pollOnce() {
	commandTimeout := source.interval * 2
	if commandTimeout < 10*time.Second {
		commandTimeout = 10 * time.Second
	}

	ctx, cancel := context.WithTimeout(context.Background(), commandTimeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, source.harborBin, "list", "--json")
	output, err := cmd.CombinedOutput()
	if err != nil {
		errorText := formatExecError(err, string(output))
		source.emit(backendStatusMsg{Text: fmt.Sprintf("harbor list --json failed: %s", errorText), IsError: true})
		return
	}

	var snapshot snapshotEnvelope
	if err := json.Unmarshal(output, &snapshot); err != nil {
		source.emit(backendStatusMsg{Text: fmt.Sprintf("Invalid JSON snapshot from harbor list --json: %v", err), IsError: true})
		return
	}

	source.emit(backendSnapshotMsg{Snapshot: snapshot})
}

func (source *harborDataSource) emit(message tea.Msg) {
	select {
	case source.events <- message:
	case <-source.stopCh:
	}
}

func formatExecError(runErr error, stderr string) string {
	trimmed := strings.TrimSpace(stderr)
	if trimmed == "" {
		return runErr.Error()
	}

	return trimmed
}
