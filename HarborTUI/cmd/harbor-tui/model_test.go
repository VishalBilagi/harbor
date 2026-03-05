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
}
