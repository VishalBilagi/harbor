package main

import (
	"context"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

type sinkConfirmation struct {
	PID         int
	ProcessName string
	Force       bool
}

type sinkResultMsg struct {
	PID    int
	Force  bool
	Output string
	Err    error
}

type model struct {
	harborBin string

	source *harborDataSource
	events <-chan tea.Msg

	width  int
	height int

	mode dataMode

	listeners []listenerRecord
	visible   []listenerRecord
	selected  int
	offset    int

	filter        string
	filterFocused bool

	confirm *sinkConfirmation

	sinkInFlight bool

	lastSnapshot time.Time
	statusText   string
	statusError  bool
}

func newModel(cfg appConfig, source *harborDataSource, events <-chan tea.Msg) model {
	initial := model{
		harborBin:  cfg.harborBin,
		source:     source,
		events:     events,
		mode:       dataModeConnecting,
		statusText: "Waiting for snapshots...",
	}

	initial.refreshVisible("")
	return initial
}

func (m model) Init() tea.Cmd {
	return waitForBackendMsg(m.events)
}

func (m model) Update(message tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := message.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil
	case backendModeMsg:
		m.mode = msg.Mode
		return m, waitForBackendMsg(m.events)
	case backendStatusMsg:
		m.statusText = msg.Text
		m.statusError = msg.IsError
		return m, waitForBackendMsg(m.events)
	case backendSnapshotMsg:
		m.applySnapshot(msg.Snapshot)
		m.statusError = false
		if m.mode == dataModeStreaming {
			m.statusText = "Streaming live snapshots"
		} else {
			m.statusText = "Snapshot refreshed"
		}
		return m, waitForBackendMsg(m.events)
	case backendClosedMsg:
		m.statusText = "Data source stopped"
		m.statusError = true
		return m, nil
	case sinkResultMsg:
		m.sinkInFlight = false
		if msg.Err != nil {
			reason := strings.TrimSpace(msg.Output)
			if reason == "" {
				reason = msg.Err.Error()
			}
			m.statusText = fmt.Sprintf("Sink failed for PID %d: %s", msg.PID, reason)
			m.statusError = true
			return m, nil
		}

		if msg.Output != "" {
			m.statusText = strings.TrimSpace(msg.Output)
		} else {
			signalName := "SIGTERM"
			if msg.Force {
				signalName = "SIGKILL"
			}
			m.statusText = fmt.Sprintf("Sent %s to PID %d", signalName, msg.PID)
		}
		m.statusError = false
		m.source.RequestReconnect()
		return m, nil
	case tea.KeyMsg:
		return m.updateKey(msg)
	default:
		return m, nil
	}
}

func (m model) View() string {
	if m.width == 0 {
		m.width = 120
	}

	builder := strings.Builder{}
	builder.WriteString(m.renderHeader())
	builder.WriteString("\n")
	builder.WriteString(m.renderFilter())
	builder.WriteString("\n")

	builder.WriteString(m.renderDashboard())

	builder.WriteString("\n")
	builder.WriteString(m.renderStatus())
	builder.WriteString("\n")
	builder.WriteString(m.renderHelp())

	if m.confirm != nil {
		builder.WriteString("\n")
		builder.WriteString(m.renderConfirmation())
	}

	return builder.String()
}

func (m model) updateKey(key tea.KeyMsg) (tea.Model, tea.Cmd) {
	keyString := key.String()

	if keyString == "ctrl+c" || keyString == "q" {
		m.source.Stop()
		return m, tea.Quit
	}

	if keyString == "r" {
		m.source.RequestReconnect()
		m.statusText = "Reconnecting data source..."
		m.statusError = false
		return m, nil
	}

	if m.confirm != nil {
		switch keyString {
		case "esc", "n":
			m.confirm = nil
			m.statusText = "Sink cancelled"
			m.statusError = false
			return m, nil
		case "y", "enter":
			confirmation := *m.confirm
			m.confirm = nil
			m.sinkInFlight = true
			signalName := "SIGTERM"
			if confirmation.Force {
				signalName = "SIGKILL"
			}
			m.statusText = fmt.Sprintf("Sending %s to PID %d...", signalName, confirmation.PID)
			m.statusError = false
			return m, runSinkCommand(m.harborBin, confirmation.PID, confirmation.Force)
		default:
			return m, nil
		}
	}

	if m.filterFocused {
		switch keyString {
		case "esc":
			m.filterFocused = false
			return m, nil
		case "enter":
			m.filterFocused = false
			return m, nil
		case "backspace", "ctrl+h":
			m.deleteFilterRune()
			return m, nil
		case "ctrl+u":
			m.filter = ""
			m.refreshVisible("")
			return m, nil
		default:
			if key.Type == tea.KeyRunes {
				m.filter += string(key.Runes)
				m.refreshVisible("")
			}
			return m, nil
		}
	}

	switch keyString {
	case "/":
		m.filterFocused = true
		return m, nil
	case "esc":
		if m.filter != "" {
			m.filter = ""
			m.refreshVisible("")
			m.statusText = "Filter cleared"
			m.statusError = false
		}
		return m, nil
	case "enter":
		return m, nil
	case "up":
		m.moveSelection(-1)
		return m, nil
	case "down":
		m.moveSelection(1)
		return m, nil
	case "pgup":
		m.moveSelection(-10)
		return m, nil
	case "pgdown":
		m.moveSelection(10)
		return m, nil
	case "home":
		m.selected = 0
		m.clampSelection()
		return m, nil
	case "end":
		m.selected = len(m.visible) - 1
		m.clampSelection()
		return m, nil
	case "k":
		return m.prepareSink(false)
	case "K", "shift+k":
		return m.prepareSink(true)
	default:
		return m, nil
	}
}

func (m *model) deleteFilterRune() {
	runes := []rune(m.filter)
	if len(runes) == 0 {
		return
	}
	m.filter = string(runes[:len(runes)-1])
	m.refreshVisible("")
}

func (m *model) moveSelection(delta int) {
	if len(m.visible) == 0 {
		m.selected = 0
		m.offset = 0
		return
	}
	m.selected += delta
	m.clampSelection()
}

func (m *model) clampSelection() {
	if len(m.visible) == 0 {
		m.selected = 0
		m.offset = 0
		return
	}

	if m.selected < 0 {
		m.selected = 0
	}
	if m.selected >= len(m.visible) {
		m.selected = len(m.visible) - 1
	}

	if m.offset > m.selected {
		m.offset = m.selected
	}
	if m.offset < 0 {
		m.offset = 0
	}
}

func (m model) prepareSink(force bool) (tea.Model, tea.Cmd) {
	if m.sinkInFlight {
		m.statusText = "A sink action is already running"
		m.statusError = true
		return m, nil
	}

	selected, ok := m.currentListener()
	if !ok {
		m.statusText = "No listener selected"
		m.statusError = true
		return m, nil
	}

	if listenerRequiresAdmin(selected) {
		m.statusText = fmt.Sprintf("PID %d requires admin privileges; sink is disabled", selected.PID)
		m.statusError = true
		return m, nil
	}

	m.confirm = &sinkConfirmation{
		PID:         selected.PID,
		ProcessName: selected.ProcessName,
		Force:       force,
	}
	m.statusText = "Confirm sink action"
	m.statusError = false
	return m, nil
}

func (m *model) applySnapshot(snapshot snapshotEnvelope) {
	currentSelectionKey := ""
	if selected, ok := m.currentListener(); ok {
		currentSelectionKey = selectedKey(selected)
	}

	m.listeners = sortedListeners(snapshot.Listeners)
	m.lastSnapshot = snapshot.GeneratedAt
	m.refreshVisible(currentSelectionKey)
}

func (m *model) refreshVisible(selectionKey string) {
	m.visible = applyFilter(m.listeners, m.filter)

	if len(m.visible) == 0 {
		m.selected = 0
		m.offset = 0
		return
	}

	if selectionKey != "" {
		for index, listener := range m.visible {
			if selectedKey(listener) == selectionKey {
				m.selected = index
				m.clampSelection()
				return
			}
		}
	}

	m.clampSelection()
}

func (m model) currentListener() (listenerRecord, bool) {
	if len(m.visible) == 0 {
		return listenerRecord{}, false
	}

	if m.selected < 0 || m.selected >= len(m.visible) {
		return listenerRecord{}, false
	}

	return m.visible[m.selected], true
}

func (m model) renderHeader() string {
	modeLabel := string(m.mode)
	if modeLabel == "" {
		modeLabel = string(dataModeConnecting)
	}

	updated := "never"
	if !m.lastSnapshot.IsZero() {
		updated = m.lastSnapshot.Local().Format("15:04:05")
	}

	visibleCount := len(m.visible)
	totalCount := len(m.listeners)
	header := fmt.Sprintf(
		"Harbor TUI | mode: %s | listeners: %d/%d | last update: %s",
		modeLabel,
		visibleCount,
		totalCount,
		updated,
	)

	return truncate(header, maxInt(m.width, 40))
}

func (m model) renderFilter() string {
	focusIndicator := " "
	if m.filterFocused {
		focusIndicator = ">"
	}
	value := m.filter
	if value == "" {
		value = "(type / to filter)"
	}

	line := fmt.Sprintf("%s Filter: %s", focusIndicator, value)
	return truncate(line, maxInt(m.width, 40))
}

func (m *model) tableWindow(maxRows int) (int, int) {
	if maxRows <= 0 {
		maxRows = 1
	}

	if len(m.visible) <= maxRows {
		m.offset = 0
		return 0, len(m.visible)
	}

	if m.selected < m.offset {
		m.offset = m.selected
	}
	if m.selected >= m.offset+maxRows {
		m.offset = m.selected - maxRows + 1
	}

	maxOffset := len(m.visible) - maxRows
	if m.offset > maxOffset {
		m.offset = maxOffset
	}
	if m.offset < 0 {
		m.offset = 0
	}

	return m.offset, minInt(len(m.visible), m.offset+maxRows)
}

func (m model) renderDashboard() string {
	totalWidth := maxInt(m.width, 80)
	panelHeight := m.height - 8
	if m.confirm != nil {
		panelHeight -= 2
	}
	if panelHeight < 8 {
		panelHeight = 8
	}

	leftWidth, rightWidth := paneWidths(totalWidth)
	listLines := m.renderListLines(maxInt(leftWidth-2, 20), maxInt(panelHeight-2, 4))
	detailLines := m.renderDetailLines(maxInt(rightWidth-2, 20))

	leftPanel := renderPanel("Listeners", listLines, leftWidth, panelHeight)
	rightPanel := renderPanel("Selected", detailLines, rightWidth, panelHeight)

	return joinHorizontal(leftPanel, rightPanel, " ")
}

func (m model) renderTable() string {
	width := maxInt(m.width-2, 40)
	maxRows := m.height - 9
	if maxRows < 5 {
		maxRows = 5
	}

	lines := m.renderListLines(width, maxRows)
	return strings.Join(lines, "\n")
}

func (m model) renderListLines(contentWidth int, maxRows int) []string {
	if len(m.visible) == 0 {
		if len(m.listeners) == 0 {
			return []string{"No active listeners in the current snapshot."}
		}
		return []string{"No listeners match the current filter."}
	}

	if maxRows < 3 {
		maxRows = 3
	}

	mutable := m
	start, end := mutable.tableWindow(maxRows)
	rows := mutable.visible[start:end]

	type tableColumn struct {
		Header   string
		MinWidth int
		Flexible bool
		Value    func(listenerRecord) string
	}

	columns := []tableColumn{
		{Header: "Port", MinWidth: 4, Value: func(listener listenerRecord) string {
			return strconv.Itoa(listener.Port)
		}},
		{Header: "Process", MinWidth: 7, Flexible: true, Value: func(listener listenerRecord) string {
			if listenerRequiresAdmin(listener) {
				return listener.ProcessName + " [admin]"
			}
			return listener.ProcessName
		}},
		{Header: "PID", MinWidth: 3, Value: func(listener listenerRecord) string {
			return strconv.Itoa(listener.PID)
		}},
		{Header: "Bind", MinWidth: 4, Flexible: true, Value: func(listener listenerRecord) string {
			if listener.BindAddress == "" {
				return "-"
			}
			return listener.BindAddress
		}},
		{Header: "Fam", MinWidth: 3, Value: func(listener listenerRecord) string {
			return listenerFamily(listener)
		}},
	}

	widths := make([]int, len(columns))
	mins := make([]int, len(columns))
	for index, column := range columns {
		maxWidth := runeLen(column.Header)
		if column.MinWidth > maxWidth {
			maxWidth = column.MinWidth
		}
		for _, row := range rows {
			valueWidth := runeLen(column.Value(row))
			if valueWidth > maxWidth {
				maxWidth = valueWidth
			}
		}
		widths[index] = maxWidth
		mins[index] = maxInt(column.MinWidth, runeLen(column.Header))
	}

	available := contentWidth - 2
	if available < 20 {
		available = 20
	}
	separatorWidth := 1
	totalWidth := func() int {
		sum := 0
		for _, width := range widths {
			sum += width
		}
		sum += (len(widths) - 1) * separatorWidth
		return sum
	}

	reduceWidth := func(flexibleOnly bool) bool {
		chosenIndex := -1
		chosenWidth := -1
		for index, width := range widths {
			if width <= mins[index] {
				continue
			}
			if flexibleOnly && !columns[index].Flexible {
				continue
			}
			if width > chosenWidth {
				chosenWidth = width
				chosenIndex = index
			}
		}

		if chosenIndex == -1 {
			return false
		}
		widths[chosenIndex]--
		return true
	}

	for totalWidth() > available {
		if reduceWidth(true) {
			continue
		}
		if reduceWidth(false) {
			continue
		}
		break
	}

	separator := strings.Repeat(" ", separatorWidth)
	lines := make([]string, 0, len(rows)+3)

	headers := make([]string, 0, len(columns))
	divider := make([]string, 0, len(columns))
	for index, column := range columns {
		headers = append(headers, pad(column.Header, widths[index]))
		divider = append(divider, strings.Repeat("-", widths[index]))
	}
	lines = append(lines, "  "+strings.Join(headers, separator))
	lines = append(lines, "  "+strings.Join(divider, separator))

	for index, row := range rows {
		absoluteIndex := start + index
		cursor := " "
		if absoluteIndex == m.selected {
			cursor = ">"
		}
		values := make([]string, 0, len(columns))
		for columnIndex, column := range columns {
			values = append(values, pad(column.Value(row), widths[columnIndex]))
		}
		lines = append(lines, cursor+" "+strings.Join(values, separator))
	}

	if len(m.visible) > len(rows) {
		lines = append(lines, fmt.Sprintf("Showing %d-%d of %d", start+1, end, len(m.visible)))
	}

	return lines
}

func (m model) renderDetails() string {
	return strings.Join(m.renderDetailLines(maxInt(m.width-2, 40)), "\n")
}

func (m model) renderDetailLines(contentWidth int) []string {
	selected, ok := m.currentListener()
	if !ok {
		return []string{"No listener selected."}
	}

	if contentWidth < 20 {
		contentWidth = 20
	}

	actionLine := "Sink actions: k SIGTERM, K SIGKILL"
	if listenerRequiresAdmin(selected) {
		actionLine = "Sink actions: disabled (admin required)"
	}

	lines := []string{
		fmt.Sprintf("[ PORT %d ]", selected.Port),
		fmt.Sprintf("%s (PID %d)", selected.ProcessName, selected.PID),
		fmt.Sprintf("Bind: %s", valueOrDash(selected.BindAddress)),
		fmt.Sprintf("Family: %s", listenerFamily(selected)),
		fmt.Sprintf("CPU: %s", listenerCPU(selected)),
		fmt.Sprintf("Memory: %s", listenerMemory(selected)),
		fmt.Sprintf("Requires admin to kill: %s", listenerAdminState(selected)),
		"",
		"Command line:",
	}

	lines = append(lines, wrapText(listenerCommand(selected), contentWidth)...)
	lines = append(lines, "")
	lines = append(lines,
		"Working directory:",
	)
	lines = append(lines, wrapText(listenerCwd(selected), contentWidth)...)
	lines = append(lines,
		"",
		"Actions/help:",
		actionLine,
		"Other: / filter, r refresh/reconnect, q quit",
	)

	return lines
}

func (m model) renderStatus() string {
	text := m.statusText
	if strings.TrimSpace(text) == "" {
		text = "Ready"
	}

	prefix := "status"
	if m.statusError {
		prefix = "error"
	}

	line := fmt.Sprintf("%s: %s", prefix, text)
	return truncate(line, maxInt(m.width, 40))
}

func (m model) renderHelp() string {
	actionHint := "k term  K kill"
	if selected, ok := m.currentListener(); ok && listenerRequiresAdmin(selected) {
		actionHint = "k/K disabled (admin required)"
	}
	if m.sinkInFlight {
		actionHint = "sink in progress..."
	}

	line := fmt.Sprintf("/ filter  ↑/↓ move  %s  r refresh/reconnect  Esc clear filter  q quit", actionHint)
	return truncate(line, maxInt(m.width, 40))
}

func (m model) renderConfirmation() string {
	if m.confirm == nil {
		return ""
	}

	signalLabel := "SIGTERM"
	if m.confirm.Force {
		signalLabel = "SIGKILL"
	}

	lines := []string{
		fmt.Sprintf("Confirm: send %s to PID %d (%s)?", signalLabel, m.confirm.PID, m.confirm.ProcessName),
		"Press y/Enter to confirm, n/Esc to cancel.",
	}
	return strings.Join(lines, "\n")
}

func paneWidths(total int) (int, int) {
	if total < 80 {
		total = 80
	}

	left := total * 56 / 100
	if left < 44 {
		left = 44
	}

	if total-left-1 < 30 {
		left = total - 31
	}

	right := total - left - 1
	return left, right
}

func renderPanel(title string, lines []string, width int, height int) []string {
	if width < 10 {
		width = 10
	}
	if height < 3 {
		height = 3
	}

	innerWidth := width - 2
	innerHeight := height - 2

	titleSegment := fmt.Sprintf(" %s ", title)
	if runeLen(titleSegment) > innerWidth {
		titleSegment = truncate(titleSegment, innerWidth)
	}
	top := "┌" + titleSegment + strings.Repeat("─", innerWidth-runeLen(titleSegment)) + "┐"
	bottom := "└" + strings.Repeat("─", innerWidth) + "┘"

	panel := make([]string, 0, height)
	panel = append(panel, top)

	for index := 0; index < innerHeight; index++ {
		content := ""
		if index < len(lines) {
			content = truncate(lines[index], innerWidth)
		}
		panel = append(panel, "│"+pad(content, innerWidth)+"│")
	}

	panel = append(panel, bottom)
	return panel
}

func joinHorizontal(left []string, right []string, gap string) string {
	leftWidth := 0
	rightWidth := 0
	if len(left) > 0 {
		leftWidth = runeLen(left[0])
	}
	if len(right) > 0 {
		rightWidth = runeLen(right[0])
	}

	lineCount := maxInt(len(left), len(right))
	lines := make([]string, 0, lineCount)
	for index := 0; index < lineCount; index++ {
		leftLine := strings.Repeat(" ", leftWidth)
		rightLine := strings.Repeat(" ", rightWidth)
		if index < len(left) {
			leftLine = pad(left[index], leftWidth)
		}
		if index < len(right) {
			rightLine = pad(right[index], rightWidth)
		}
		lines = append(lines, leftLine+gap+rightLine)
	}

	return strings.Join(lines, "\n")
}

func wrapText(value string, width int) []string {
	if width <= 0 {
		return []string{""}
	}

	trimmed := strings.TrimSpace(value)
	if trimmed == "" || trimmed == "-" {
		return []string{"-"}
	}

	paragraphs := strings.Split(trimmed, "\n")
	result := make([]string, 0, len(paragraphs))

	for paragraphIndex, paragraph := range paragraphs {
		words := strings.Fields(paragraph)
		if len(words) == 0 {
			result = append(result, "")
			continue
		}

		current := words[0]
		for _, rawWord := range words[1:] {
			word := rawWord
			candidate := current + " " + word
			if runeLen(candidate) <= width {
				current = candidate
				continue
			}

			result = append(result, truncate(current, width))

			for runeLen(word) > width {
				runes := []rune(word)
				result = append(result, string(runes[:width]))
				word = string(runes[width:])
			}
			current = word
		}

		for runeLen(current) > width {
			runes := []rune(current)
			result = append(result, string(runes[:width]))
			current = string(runes[width:])
		}
		result = append(result, current)

		if paragraphIndex < len(paragraphs)-1 {
			result = append(result, "")
		}
	}

	return result
}

func valueOrDash(value string) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return "-"
	}
	return trimmed
}

func runSinkCommand(harborBin string, pid int, force bool) tea.Cmd {
	return func() tea.Msg {
		args := []string{"sink", "--pid", strconv.Itoa(pid)}
		if force {
			args = append(args, "--force")
		}
		args = append(args, "--yes")

		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()

		cmd := exec.CommandContext(ctx, harborBin, args...)
		output, err := cmd.CombinedOutput()
		return sinkResultMsg{
			PID:    pid,
			Force:  force,
			Output: strings.TrimSpace(string(output)),
			Err:    err,
		}
	}
}

func waitForBackendMsg(events <-chan tea.Msg) tea.Cmd {
	return func() tea.Msg {
		if events == nil {
			return nil
		}

		msg, ok := <-events
		if !ok {
			return backendClosedMsg{}
		}

		return msg
	}
}

func maxInt(left int, right int) int {
	if left > right {
		return left
	}
	return right
}

func minInt(left int, right int) int {
	if left < right {
		return left
	}
	return right
}
