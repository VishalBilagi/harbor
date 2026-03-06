package main

import (
	"strings"
	"testing"
	"time"

	"github.com/charmbracelet/x/ansi"
)

func TestPrepareSinkDisablesAdminRequiredRows(t *testing.T) {
	requiresAdmin := true
	listeners := []listenerRecord{
		{Port: 3000, PID: 999, ProcessName: "root-owned", RequiresAdminToKill: &requiresAdmin},
	}

	m := model{
		listeners: listeners,
		visible:   listeners,
		selected:  0,
	}

	updatedModel, _ := m.prepareSink(false)
	updated := updatedModel.(model)

	if !updated.statusError {
		t.Fatalf("expected statusError=true when sink is disabled")
	}
	if updated.confirm != nil {
		t.Fatalf("expected no confirmation dialog when sink is disabled")
	}
	if !strings.Contains(updated.statusText, "sink is disabled") {
		t.Fatalf("expected disabled sink status, got: %q", updated.statusText)
	}
}

func TestRenderHelpShowsAdminDisabledHintForSelectedRow(t *testing.T) {
	requiresAdmin := true
	listeners := []listenerRecord{
		{Port: 3000, PID: 111, ProcessName: "root-owned", RequiresAdminToKill: &requiresAdmin},
	}

	m := model{
		width:     140,
		height:    20,
		listeners: listeners,
		visible:   listeners,
		selected:  0,
	}

	help := m.renderHelp()
	if !strings.Contains(help, "k/K disabled (admin required)") {
		t.Fatalf("expected admin disabled help hint, got: %q", help)
	}
}

func TestRenderTableMarksAdminRows(t *testing.T) {
	requiresAdmin := true
	listeners := []listenerRecord{
		{Port: 8080, PID: 200, ProcessName: "nginx", BindAddress: "*", Family: "ipv4", RequiresAdminToKill: &requiresAdmin},
	}

	m := model{
		width:     140,
		height:    20,
		listeners: listeners,
		visible:   listeners,
		selected:  0,
	}

	table := ansi.Strip(m.renderTable())
	if !strings.Contains(table, "nginx") || !strings.Contains(table, "admin") {
		t.Fatalf("expected admin marker in table row, got: %q", table)
	}
	if strings.Contains(table, "Cmd") || strings.Contains(table, "Cwd") {
		t.Fatalf("expected compact list columns without command/cwd, got: %q", table)
	}
}

func TestViewRendersTwoPaneDashboard(t *testing.T) {
	command := "python app.py --port 8080"
	cwd := "/tmp/dashboard"
	listeners := []listenerRecord{
		{
			Port:        8080,
			PID:         321,
			ProcessName: "python",
			BindAddress: "0.0.0.0",
			Family:      "ipv4",
			CommandLine: &command,
			Cwd:         &cwd,
		},
	}

	m := model{
		width:     120,
		height:    24,
		listeners: listeners,
		visible:   listeners,
		selected:  0,
	}

	view := m.View()
	if !strings.Contains(view, "┌ Listeners") {
		t.Fatalf("expected listeners pane in dashboard view, got: %q", view)
	}
	if !strings.Contains(view, "┌ Selected") {
		t.Fatalf("expected selected details pane in dashboard view, got: %q", view)
	}
}

func TestRenderDetailLinesShowsPortBadgeAndWrappedDetails(t *testing.T) {
	command := "/usr/local/bin/node /tmp/service/server.js --watch --inspect"
	cwd := "/tmp/service"
	listeners := []listenerRecord{
		{
			Port:        4567,
			PID:         876,
			ProcessName: "node",
			BindAddress: "127.0.0.1",
			Family:      "ipv4",
			CommandLine: &command,
			Cwd:         &cwd,
		},
	}

	m := model{
		width:     120,
		height:    24,
		listeners: listeners,
		visible:   listeners,
		selected:  0,
	}

	lines := m.renderDetailLines(24)
	joined := ansi.Strip(strings.Join(lines, " "))
	if len(lines) == 0 {
		t.Fatalf("expected detail lines")
	}
	firstLine := ansi.Strip(lines[0])
	if !strings.Contains(firstLine, "4567") || !strings.Contains(firstLine, "node") {
		t.Fatalf("expected port+process hero line in details, got: %q", firstLine)
	}
	if !strings.Contains(joined, "/usr/local/bin/node") || !strings.Contains(joined, "--inspect") {
		t.Fatalf("expected command details in panel output, got: %q", joined)
	}
	if !strings.Contains(joined, "/tmp/service") {
		t.Fatalf("expected cwd details in panel output, got: %q", joined)
	}
}

func TestStreamStateBadgeReflectsModeAndHealth(t *testing.T) {
	streaming := model{mode: dataModeStreaming, lastSnapshot: time.Now()}
	if !strings.Contains(ansi.Strip(streaming.streamStateBadge()), "stream live") {
		t.Fatalf("expected live stream badge in streaming mode")
	}

	stale := model{mode: dataModeStreaming, lastSnapshot: time.Now().Add(-30 * time.Second)}
	if !strings.Contains(ansi.Strip(stale.streamStateBadge()), "stream stale") {
		t.Fatalf("expected stale stream badge for old snapshots")
	}

	reconnecting := model{mode: dataModeConnecting}
	if !strings.Contains(ansi.Strip(reconnecting.streamStateBadge()), "stream reconnecting") {
		t.Fatalf("expected reconnecting badge while connecting")
	}
}

func TestBindClassificationSupportsSemanticTags(t *testing.T) {
	if bindClassification("127.0.0.1") != "localhost" {
		t.Fatalf("expected localhost classification for 127.0.0.1")
	}
	if bindClassification("0.0.0.0") != "wildcard" {
		t.Fatalf("expected wildcard classification for 0.0.0.0")
	}
	if bindClassification("192.168.1.4") != "other" {
		t.Fatalf("expected other classification for private interface")
	}
}
