package main

import (
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
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
	stripped := ansi.Strip(help)
	if !strings.Contains(stripped, "disabled (admin required)") {
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
	if !strings.Contains(ansi.Strip(reconnecting.streamStateBadge()), "reconnecting") {
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

func TestRenderFilterShowsInputAndCountWhenFocused(t *testing.T) {
	listeners := []listenerRecord{
		{Port: 8080, PID: 100, ProcessName: "api"},
		{Port: 5432, PID: 200, ProcessName: "postgres"},
		{Port: 3000, PID: 300, ProcessName: "web"},
	}
	visible := listeners[:2]

	m := model{
		width:         140,
		listeners:     listeners,
		visible:       visible,
		filterFocused: true,
		filter:        "post",
	}

	filterLine := ansi.Strip(m.renderFilter())
	if !strings.Contains(filterLine, "Filter") || !strings.Contains(filterLine, "2/3") {
		t.Fatalf("expected focused filter line with count, got: %q", filterLine)
	}
	if !strings.Contains(filterLine, "▏") {
		t.Fatalf("expected focused filter cursor marker, got: %q", filterLine)
	}
}

func TestRenderListLinesShowsControlChipsAndWildcardMarker(t *testing.T) {
	listeners := []listenerRecord{
		{Port: 8080, PID: 200, ProcessName: "nginx", BindAddress: "*", Family: "ipv4"},
		{Port: 3000, PID: 300, ProcessName: "web", BindAddress: "127.0.0.1", Family: "ipv4"},
	}

	m := model{
		width:     140,
		height:    20,
		listeners: listeners,
		visible:   listeners,
		selected:  0,
	}

	lines := m.renderListLines(120, 8)
	joined := ansi.Strip(strings.Join(lines, "\n"))
	if !strings.Contains(joined, "Sort:") || !strings.Contains(joined, "Port") || !strings.Contains(joined, "Filter: All") {
		t.Fatalf("expected sort/filter chips at top of list, got: %q", joined)
	}
	if !strings.Contains(joined, "⚠ wildcard") {
		t.Fatalf("expected wildcard warning glyph marker, got: %q", joined)
	}
}

func TestRenderDetailLinesShowsAdminSafetyAndDeliberateActions(t *testing.T) {
	requiresAdmin := true
	command := "/usr/sbin/systemservice --watch"
	cwd := "/var/root"
	listeners := []listenerRecord{
		{
			Port:                8443,
			PID:                 42,
			ProcessName:         "systemservice",
			BindAddress:         "0.0.0.0",
			Family:              "ipv4",
			CommandLine:         &command,
			Cwd:                 &cwd,
			RequiresAdminToKill: &requiresAdmin,
		},
	}

	m := model{
		width:     140,
		height:    24,
		listeners: listeners,
		visible:   listeners,
		selected:  0,
	}

	joined := ansi.Strip(strings.Join(m.renderDetailLines(60), "\n"))
	if !strings.Contains(joined, "Ownership: admin-owned process; sink disabled") {
		t.Fatalf("expected explicit admin ownership safety line, got: %q", joined)
	}
	if !strings.Contains(joined, "disabled (admin required)") {
		t.Fatalf("expected actions to show disabled admin-required state, got: %q", joined)
	}
	if !strings.Contains(joined, "Intent gate: unavailable while admin-required") {
		t.Fatalf("expected explicit intent-gate note for admin-owned process, got: %q", joined)
	}
}

func TestCompactPathKeepsTailSegments(t *testing.T) {
	path := "/Users/vishal/workspaces/harbor/cmd/harbor-tui"
	compact := compactPath(path, 20)
	if !strings.Contains(compact, "cmd/harbor-tui") {
		t.Fatalf("expected compact path to retain tail segments, got: %q", compact)
	}
	if runeLen(compact) > 20 {
		t.Fatalf("expected compact path to respect width, got: %q", compact)
	}
}

func TestRenderDetailLinesShowsForceIntentGateForUserOwnedProcess(t *testing.T) {
	requiresAdmin := false
	command := "/usr/local/bin/node server.js"
	cwd := "/Users/vishal/projects/harbor/service"
	listeners := []listenerRecord{
		{
			Port:                3000,
			PID:                 4242,
			ProcessName:         "node",
			BindAddress:         "127.0.0.1",
			Family:              "ipv4",
			CommandLine:         &command,
			Cwd:                 &cwd,
			RequiresAdminToKill: &requiresAdmin,
		},
	}

	m := model{
		width:     140,
		height:    24,
		listeners: listeners,
		visible:   listeners,
		selected:  0,
	}

	joined := ansi.Strip(strings.Join(m.renderDetailLines(60), "\n"))
	if !strings.Contains(joined, "Ownership: user-owned process; sink enabled") {
		t.Fatalf("expected explicit user-owned safety line, got: %q", joined)
	}
	if !strings.Contains(joined, "Intent gate: ✕K opens confirmation before sending SIGKILL") {
		t.Fatalf("expected explicit force-kill intent gate for user-owned process, got: %q", joined)
	}
	if !strings.Contains(joined, "compact:") {
		t.Fatalf("expected compact cwd preview line, got: %q", joined)
	}
}

func TestSetListFilterAppliesChipFilterModes(t *testing.T) {
	adminRequired := true
	listeners := []listenerRecord{
		{Port: 8080, PID: 10, ProcessName: "ipv4", Family: "ipv4", BindAddress: "127.0.0.1", RequiresAdminToKill: &adminRequired},
		{Port: 9090, PID: 20, ProcessName: "ipv6", Family: "ipv6", BindAddress: "::1"},
		{Port: 3000, PID: 30, ProcessName: "wild", Family: "ipv4", BindAddress: "0.0.0.0"},
	}

	m := model{
		listeners:   listeners,
		visible:     listeners,
		listFilter:  listFilterAll,
		statusText:  "Ready",
		statusError: false,
	}

	m.setListFilter(listFilterIPv6)
	if len(m.visible) != 1 || m.visible[0].PID != 20 {
		t.Fatalf("expected only IPv6 listener after list filter, got: %#v", m.visible)
	}

	m.setListFilter(listFilterWildcard)
	if len(m.visible) != 1 || m.visible[0].PID != 30 {
		t.Fatalf("expected only wildcard listener after list filter, got: %#v", m.visible)
	}

	m.setListFilter(listFilterUserOwned)
	if len(m.visible) != 2 {
		t.Fatalf("expected two user-owned listeners, got: %#v", m.visible)
	}
}

func TestUpdateKeyNumericChipShortcutsSwitchListFilter(t *testing.T) {
	listeners := []listenerRecord{
		{Port: 8080, PID: 10, ProcessName: "ipv4", Family: "ipv4", BindAddress: "127.0.0.1"},
		{Port: 9090, PID: 20, ProcessName: "ipv6", Family: "ipv6", BindAddress: "::1"},
	}

	m := model{
		listeners:   listeners,
		visible:     listeners,
		listFilter:  listFilterAll,
		statusText:  "Ready",
		statusError: false,
	}

	nextModel, _ := m.updateKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("3")})
	updated := nextModel.(model)
	if updated.listFilter != listFilterIPv6 {
		t.Fatalf("expected numeric shortcut to select IPv6 chip, got: %s", updated.listFilter)
	}
	if len(updated.visible) != 1 || updated.visible[0].PID != 20 {
		t.Fatalf("expected visible list filtered to IPv6, got: %#v", updated.visible)
	}
}
