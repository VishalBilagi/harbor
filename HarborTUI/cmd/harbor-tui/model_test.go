package main

import (
	"strings"
	"testing"
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

	table := m.renderTable()
	if !strings.Contains(table, "nginx [admin]") {
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
	joined := strings.Join(lines, " ")
	if len(lines) == 0 || lines[0] != "[ PORT 4567 ]" {
		t.Fatalf("expected big port badge in detail header, got: %#v", lines)
	}
	if !strings.Contains(joined, "/usr/local/bin/node") || !strings.Contains(joined, "--inspect") {
		t.Fatalf("expected command details in panel output, got: %q", joined)
	}
	if !strings.Contains(joined, "/tmp/service") {
		t.Fatalf("expected cwd details in panel output, got: %q", joined)
	}
}
