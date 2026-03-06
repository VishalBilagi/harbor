package main

import (
	"context"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
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

type tuiStyles struct {
	headerBar         lipgloss.Style
	headerBadge       lipgloss.Style
	headerMeta        lipgloss.Style
	streamWarning     lipgloss.Style
	streamError       lipgloss.Style
	filterLabel       lipgloss.Style
	filterInput       lipgloss.Style
	filterPlaceholder lipgloss.Style
	filterCount       lipgloss.Style
	filterIdle        lipgloss.Style
	muted             lipgloss.Style
	chipActive        lipgloss.Style
	chipIdle          lipgloss.Style
	chipFuture        lipgloss.Style
	portBadge         lipgloss.Style
	portBadgeSelected lipgloss.Style
	process           lipgloss.Style
	processSelected   lipgloss.Style
	pid               lipgloss.Style
	pidSelected       lipgloss.Style
	tagLocalhost      lipgloss.Style
	tagWildcard       lipgloss.Style
	tagProtected      lipgloss.Style
	tagNeutral        lipgloss.Style
	tagFamily         lipgloss.Style
	rowSelected       lipgloss.Style
	rowNormal         lipgloss.Style
	statusNormal      lipgloss.Style
	statusError       lipgloss.Style
	helpKey           lipgloss.Style
	helpDangerKey     lipgloss.Style
	helpAction        lipgloss.Style
	helpSeparator     lipgloss.Style
	detailSection     lipgloss.Style
	detailRule        lipgloss.Style
	detailBody        lipgloss.Style
	detailDanger      lipgloss.Style
	detailSafe        lipgloss.Style
}

var styles = tuiStyles{
	headerBar: lipgloss.NewStyle().
		Foreground(lipgloss.Color("#d8e7ff")),
	headerBadge: lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("#66D9FF")).
		Background(lipgloss.Color("#10293A")).
		Padding(0, 1),
	headerMeta: lipgloss.NewStyle().Foreground(lipgloss.Color("#A9B8D0")),
	streamWarning: lipgloss.NewStyle().
		Foreground(lipgloss.Color("#F0C674")).
		Background(lipgloss.Color("#3A2C12")).
		Padding(0, 1),
	streamError: lipgloss.NewStyle().
		Foreground(lipgloss.Color("#F28B82")).
		Background(lipgloss.Color("#3F1B1D")).
		Padding(0, 1),
	filterLabel: lipgloss.NewStyle().Foreground(lipgloss.Color("#91A6C8")),
	filterInput: lipgloss.NewStyle().
		Foreground(lipgloss.Color("#E7F3FF")).
		Background(lipgloss.Color("#1B2E46")),
	filterPlaceholder: lipgloss.NewStyle().
		Foreground(lipgloss.Color("#8FA1BC")).
		Background(lipgloss.Color("#1B2E46")),
	filterCount: lipgloss.NewStyle().
		Foreground(lipgloss.Color("#CFE7FF")).
		Background(lipgloss.Color("#223A54")).
		Padding(0, 1),
	filterIdle: lipgloss.NewStyle().Foreground(lipgloss.Color("#8FA1BC")),
	muted:      lipgloss.NewStyle().Foreground(lipgloss.Color("#8FA1BC")),
	chipActive: lipgloss.NewStyle().
		Foreground(lipgloss.Color("#E3F3FF")).
		Background(lipgloss.Color("#1A3249")).
		Padding(0, 1),
	chipIdle: lipgloss.NewStyle().
		Foreground(lipgloss.Color("#B8CBE4")).
		Background(lipgloss.Color("#202B3E")).
		Padding(0, 1),
	chipFuture: lipgloss.NewStyle().
		Foreground(lipgloss.Color("#97A8C1")).
		Background(lipgloss.Color("#172132")).
		Padding(0, 1),
	portBadge: lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("#57D7FF")).
		Background(lipgloss.Color("#103243")).
		Padding(0, 1),
	portBadgeSelected: lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("#00151F")).
		Background(lipgloss.Color("#8CE5FF")).
		Padding(0, 1),
	process:         lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#E7EEF9")),
	processSelected: lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#F4FAFF")),
	pid:             lipgloss.NewStyle().Foreground(lipgloss.Color("#8F9AB0")),
	pidSelected:     lipgloss.NewStyle().Foreground(lipgloss.Color("#B6C4DE")),
	tagLocalhost: lipgloss.NewStyle().
		Foreground(lipgloss.Color("#65C3FF")).
		Background(lipgloss.Color("#11364A")).
		Padding(0, 1),
	tagWildcard: lipgloss.NewStyle().
		Foreground(lipgloss.Color("#F4C26E")).
		Background(lipgloss.Color("#3B2B12")).
		Padding(0, 1),
	tagProtected: lipgloss.NewStyle().
		Foreground(lipgloss.Color("#F19999")).
		Background(lipgloss.Color("#3E1E25")).
		Padding(0, 1),
	tagNeutral: lipgloss.NewStyle().
		Foreground(lipgloss.Color("#C0CFEA")).
		Background(lipgloss.Color("#1C2738")).
		Padding(0, 1),
	tagFamily: lipgloss.NewStyle().
		Foreground(lipgloss.Color("#C9B8F4")).
		Background(lipgloss.Color("#2A243D")).
		Padding(0, 1),
	rowSelected: lipgloss.NewStyle().
		Background(lipgloss.Color("#102743")),
	rowNormal:    lipgloss.NewStyle(),
	statusNormal: lipgloss.NewStyle().Foreground(lipgloss.Color("#A7BCD8")),
	statusError:  lipgloss.NewStyle().Foreground(lipgloss.Color("#F4A7A0")).Bold(true),
	helpKey: lipgloss.NewStyle().
		Foreground(lipgloss.Color("#DCEEFF")).
		Background(lipgloss.Color("#21354D")).
		Padding(0, 1),
	helpDangerKey: lipgloss.NewStyle().
		Foreground(lipgloss.Color("#FFE1E1")).
		Background(lipgloss.Color("#4A2329")).
		Padding(0, 1),
	helpAction:    lipgloss.NewStyle().Foreground(lipgloss.Color("#9EB0C8")),
	helpSeparator: lipgloss.NewStyle().Foreground(lipgloss.Color("#6E83A1")),
	detailSection: lipgloss.NewStyle().
		Foreground(lipgloss.Color("#9CB5D6")).
		Bold(true),
	detailRule:   lipgloss.NewStyle().Foreground(lipgloss.Color("#2A3F5E")),
	detailBody:   lipgloss.NewStyle().Foreground(lipgloss.Color("#D3E2F8")),
	detailDanger: lipgloss.NewStyle().Foreground(lipgloss.Color("#F4B3B3")).Bold(true),
	detailSafe:   lipgloss.NewStyle().Foreground(lipgloss.Color("#9BD7B0")),
}

type listFilterMode string

const (
	listFilterAll       listFilterMode = "all"
	listFilterIPv4      listFilterMode = "ipv4"
	listFilterIPv6      listFilterMode = "ipv6"
	listFilterWildcard  listFilterMode = "wildcard"
	listFilterUserOwned listFilterMode = "user-owned"
)

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
	listFilter    listFilterMode

	confirm *sinkConfirmation

	sinkInFlight bool

	lastSnapshot time.Time
	statusText   string
	statusError  bool
	backendError bool
}

func newModel(cfg appConfig, source *harborDataSource, events <-chan tea.Msg) model {
	initial := model{
		harborBin:  cfg.harborBin,
		source:     source,
		events:     events,
		mode:       dataModeConnecting,
		statusText: "Waiting for snapshots...",
		listFilter: listFilterAll,
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
		m.backendError = msg.IsError
		return m, waitForBackendMsg(m.events)
	case backendSnapshotMsg:
		m.applySnapshot(msg.Snapshot)
		m.statusError = false
		m.backendError = false
		if m.mode == dataModeStreaming {
			m.statusText = "Streaming live snapshots"
		} else {
			m.statusText = "Snapshot refreshed"
		}
		return m, waitForBackendMsg(m.events)
	case backendClosedMsg:
		m.statusText = "Data source stopped"
		m.statusError = true
		m.backendError = true
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
			m.backendError = false
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
		m.backendError = false
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
		m.backendError = false
		return m, nil
	}

	if m.confirm != nil {
		switch keyString {
		case "esc", "n":
			m.confirm = nil
			m.statusText = "Sink cancelled"
			m.statusError = false
			m.backendError = false
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
			m.backendError = false
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
	case "1":
		m.setListFilter(listFilterAll)
		return m, nil
	case "2":
		m.setListFilter(listFilterIPv4)
		return m, nil
	case "3":
		m.setListFilter(listFilterIPv6)
		return m, nil
	case "4":
		m.setListFilter(listFilterWildcard)
		return m, nil
	case "5":
		m.setListFilter(listFilterUserOwned)
		return m, nil
	case "tab":
		m.cycleListFilter(1)
		return m, nil
	case "shift+tab":
		m.cycleListFilter(-1)
		return m, nil
	case "s":
		m.statusText = "Sort: Port"
		m.statusError = false
		m.backendError = false
		return m, nil
	case "esc":
		if m.filter != "" {
			m.filter = ""
			m.refreshVisible("")
			m.statusText = "Filter cleared"
			m.statusError = false
			m.backendError = false
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
	filtered := applyFilter(m.listeners, m.filter)
	m.visible = applyListFilter(filtered, m.listFilter)

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

func (m *model) setListFilter(mode listFilterMode) {
	selectionKey := ""
	if selected, ok := m.currentListener(); ok {
		selectionKey = selectedKey(selected)
	}

	m.listFilter = mode
	m.refreshVisible(selectionKey)

	statusSuffix := "All"
	switch mode {
	case listFilterIPv4:
		statusSuffix = "IPv4"
	case listFilterIPv6:
		statusSuffix = "IPv6"
	case listFilterWildcard:
		statusSuffix = "Wildcard"
	case listFilterUserOwned:
		statusSuffix = "User-owned"
	}
	m.statusText = "Filter: " + statusSuffix
	m.statusError = false
	m.backendError = false
}

func (m *model) cycleListFilter(direction int) {
	order := []listFilterMode{
		listFilterAll,
		listFilterIPv4,
		listFilterIPv6,
		listFilterWildcard,
		listFilterUserOwned,
	}

	currentIndex := 0
	for index, mode := range order {
		if mode == m.listFilter {
			currentIndex = index
			break
		}
	}

	nextIndex := (currentIndex + direction) % len(order)
	if nextIndex < 0 {
		nextIndex += len(order)
	}

	m.setListFilter(order[nextIndex])
}

func applyListFilter(listeners []listenerRecord, mode listFilterMode) []listenerRecord {
	if mode == listFilterAll {
		return listeners
	}

	filtered := make([]listenerRecord, 0, len(listeners))
	for _, listener := range listeners {
		include := false
		switch mode {
		case listFilterIPv4:
			include = strings.EqualFold(listenerFamily(listener), "IPv4")
		case listFilterIPv6:
			include = strings.EqualFold(listenerFamily(listener), "IPv6")
		case listFilterWildcard:
			include = bindClassification(listener.BindAddress) == "wildcard"
		case listFilterUserOwned:
			include = !listenerRequiresAdmin(listener)
		default:
			include = true
		}

		if include {
			filtered = append(filtered, listener)
		}
	}

	return filtered
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
	age := m.snapshotAge()
	ageText := styles.streamWarning.Render("last update --:--:--")
	if !m.lastSnapshot.IsZero() {
		label := "last update " + m.lastSnapshot.Local().Format("15:04:05")
		switch {
		case age >= 20*time.Second:
			ageText = styles.streamError.Render(label)
		case age >= 8*time.Second:
			ageText = styles.streamWarning.Render(label)
		default:
			ageText = styles.headerMeta.Render(label)
		}
	}

	left := lipgloss.JoinHorizontal(
		lipgloss.Top,
		styles.headerBadge.Render("HARBOR"),
	)
	right := lipgloss.JoinHorizontal(
		lipgloss.Top,
		styles.headerMeta.Render(fmt.Sprintf("listeners %d/%d", len(m.visible), len(m.listeners))),
		" ",
		ageText,
	)
	line := lipgloss.JoinHorizontal(lipgloss.Top, left, "  ", right)
	return truncate(styles.headerBar.Render(line), maxInt(m.width, 40))
}

func (m model) renderFilter() string {
	count := fmt.Sprintf("%d/%d", len(m.visible), len(m.listeners))

	if m.filterFocused {
		value := strings.TrimSpace(m.filter)
		if value == "" {
			value = "type to filter"
			value = styles.filterPlaceholder.Render(" " + value + " ")
		} else {
			value = styles.filterInput.Render(" " + value + " ")
		}

		box := lipgloss.NewStyle().
			BorderStyle(lipgloss.NormalBorder()).
			BorderLeft(true).
			BorderRight(true).
			BorderForeground(lipgloss.Color("#2B4A6B")).
			Padding(0, 1).
			Render(value + styles.filterInput.Render(" ▏"))

		line := lipgloss.JoinHorizontal(
			lipgloss.Top,
			styles.filterLabel.Render("Filter"),
			box,
			styles.filterCount.Render(count),
			styles.muted.Render("Esc done"),
		)
		return truncate(line, maxInt(m.width, 40))
	}

	if strings.TrimSpace(m.filter) != "" {
		line := lipgloss.JoinHorizontal(
			lipgloss.Top,
			styles.filterLabel.Render("Filter"),
			styles.chipActive.Render("query: "+m.filter),
			styles.filterCount.Render(count),
			styles.muted.Render("(press / to edit, Esc to clear)"),
		)
		return truncate(line, maxInt(m.width, 40))
	}

	line := lipgloss.JoinHorizontal(
		lipgloss.Top,
		styles.filterLabel.Render("Filter"),
		styles.chipIdle.Render("all listeners"),
		styles.filterCount.Render(count),
		styles.filterIdle.Render("type / to search port, process, PID, bind, cmd, cwd"),
	)
	return truncate(line, maxInt(m.width, 40))
}

func (m model) snapshotAge() time.Duration {
	if m.lastSnapshot.IsZero() {
		return 0
	}

	age := time.Since(m.lastSnapshot)
	if age < 0 {
		return 0
	}
	return age
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
			return []string{styles.muted.Render("No active listeners in the current snapshot.")}
		}
		return []string{styles.muted.Render("No listeners match the current filter.")}
	}

	if maxRows < 3 {
		maxRows = 3
	}

	lines := make([]string, 0, maxRows)
	showControls := maxRows >= 6
	if showControls {
		lines = append(lines, m.renderListControlChips(contentWidth))
	}

	availableLines := maxRows - len(lines)
	showHeader := availableLines >= 2
	rowSlots := availableLines
	if showHeader {
		rowSlots--
	}
	if rowSlots < 1 {
		rowSlots = 1
	}

	widths := computeListColumnWidths(contentWidth)
	if showHeader {
		header := "  " + renderListTableLine(
			widths,
			"PORT",
			"PROCESS",
			"PID",
			"FAMILY",
			"BIND",
			"ACCESS",
		)
		lines = append(lines, truncate(styles.filterLabel.Render(header), contentWidth))
	}

	mutable := m
	start, end := mutable.tableWindow(rowSlots)
	rows := mutable.visible[start:end]

	for index, row := range rows {
		if len(lines)+1 > maxRows {
			break
		}

		absoluteIndex := start + index
		selected := absoluteIndex == m.selected

		bind := listBindValue(row.BindAddress)
		access := styles.detailSafe.Render("user")
		if listenerRequiresAdmin(row) {
			access = styles.detailDanger.Render("admin")
		}
		rowLine := renderListTableLine(
			widths,
			strconv.Itoa(row.Port),
			valueOrDash(row.ProcessName),
			strconv.Itoa(row.PID),
			listenerFamily(row),
			bind,
			access,
		)

		if selected {
			selectedLineStyle := styles.rowSelected.Width(contentWidth)
			lines = append(lines, selectedLineStyle.Render(pad(truncate("▌ "+rowLine, contentWidth), contentWidth)))
			continue
		}
		lines = append(lines, truncate("  "+rowLine, contentWidth))
	}

	if len(m.visible) > len(rows) && len(lines) < maxRows {
		lines = append(lines, styles.muted.Render(fmt.Sprintf("Showing %d-%d of %d", start+1, end, len(m.visible))))
	}

	if len(lines) > maxRows {
		lines = lines[:maxRows]
	}

	return lines
}

type listColumnWidths struct {
	port    int
	process int
	pid     int
	family  int
	bind    int
	access  int
}

func computeListColumnWidths(contentWidth int) listColumnWidths {
	usable := contentWidth - 2
	if usable < 20 {
		usable = 20
	}

	widths := listColumnWidths{
		port:   5,
		pid:    7,
		family: 6,
		access: 6,
	}

	const gaps = 5
	remaining := usable - widths.port - widths.pid - widths.family - widths.access - gaps
	if remaining < 2 {
		remaining = 2
	}

	if remaining >= 18 {
		widths.process = remaining * 3 / 5
	} else {
		widths.process = remaining / 2
	}
	if widths.process < 1 {
		widths.process = 1
	}

	widths.bind = remaining - widths.process
	if widths.bind < 1 {
		widths.bind = 1
		widths.process = remaining - widths.bind
	}
	if widths.process < 1 {
		widths.process = 1
	}

	return widths
}

func renderListTableLine(widths listColumnWidths, port string, process string, pid string, family string, bind string, access string) string {
	columns := []string{
		pad(port, widths.port),
		pad(process, widths.process),
		pad(pid, widths.pid),
		pad(family, widths.family),
		pad(bind, widths.bind),
		pad(access, widths.access),
	}
	return strings.Join(columns, " ")
}

func listBindValue(bindAddress string) string {
	address := valueOrDash(bindAddress)
	switch bindClassification(address) {
	case "wildcard":
		return "⚠ wildcard " + address
	case "localhost":
		return "localhost " + address
	default:
		return address
	}
}

func (m model) renderDetails() string {
	return strings.Join(m.renderDetailLines(maxInt(m.width-2, 40)), "\n")
}

func (m model) renderDetailLines(contentWidth int) []string {
	selected, ok := m.currentListener()
	if !ok {
		return []string{"No listener selected."}
	}

	if contentWidth < 24 {
		contentWidth = 24
	}

	primary := lipgloss.JoinHorizontal(
		lipgloss.Top,
		styles.portBadgeSelected.Render(strconv.Itoa(selected.Port)),
		styles.processSelected.Render(valueOrDash(selected.ProcessName)),
		styles.pidSelected.Render(fmt.Sprintf("pid %d", selected.PID)),
	)
	bindChip := styles.tagNeutral.Render("bind " + valueOrDash(selected.BindAddress))
	switch bindClassification(selected.BindAddress) {
	case "wildcard":
		bindChip = styles.tagWildcard.Render("⚠ wildcard " + valueOrDash(selected.BindAddress))
	case "localhost":
		bindChip = styles.tagLocalhost.Render("localhost " + valueOrDash(selected.BindAddress))
	}

	metaChips := []string{
		bindChip,
		styles.tagFamily.Render(listenerFamily(selected)),
	}
	adminRequired := listenerRequiresAdmin(selected)
	if adminRequired {
		metaChips = append(metaChips, styles.tagProtected.Render("admin required"))
	} else {
		metaChips = append(metaChips, styles.tagLocalhost.Render("user-owned"))
	}
	meta := lipgloss.JoinHorizontal(lipgloss.Top, metaChips...)

	rule := styles.detailRule.Render(strings.Repeat("─", minInt(contentWidth, 36)))
	safetyLine := styles.detailSafe.Render("Ownership: user-owned process; sink enabled")
	if adminRequired {
		safetyLine = styles.detailDanger.Render("Ownership: admin-owned process; sink disabled")
	}

	actionLine := lipgloss.JoinHorizontal(
		lipgloss.Top,
		m.helpSegment("k", "term"),
		m.helpSegmentDanger("✕K", "force"),
		styles.helpAction.Render("requires confirm"),
	)
	actionSafety := styles.detailDanger.Render("Intent gate: ✕K opens confirmation before sending SIGKILL")
	if adminRequired {
		actionLine = m.helpSegment("k/K", "disabled (admin required)")
		actionSafety = styles.helpAction.Render("Intent gate: unavailable while admin-required")
	}

	lines := []string{
		primary,
		meta,
		"",
		rule,
		styles.detailSection.Render("Runtime"),
		m.detailMetricLine("CPU", listenerCPU(selected)),
		m.detailMetricLine("MEM", listenerMemory(selected)),
		m.detailMetricLine("Admin", listenerAdminState(selected)),
		"",
		styles.detailSection.Render("Command"),
	}

	for _, line := range wrapText(listenerCommand(selected), contentWidth) {
		lines = append(lines, styles.detailBody.Render(line))
	}
	lines = append(lines, "")
	lines = append(lines,
		styles.detailSection.Render("Working Directory"),
	)
	cwdValue := listenerCwd(selected)
	if cwdValue != "-" {
		lines = append(lines, styles.muted.Render("compact: "+compactPath(cwdValue, maxInt(contentWidth-9, 16))))
	}
	for _, line := range wrapText(listenerCwd(selected), contentWidth) {
		lines = append(lines, styles.detailBody.Render(line))
	}
	lines = append(lines,
		"",
		styles.detailSection.Render("Safety"),
		safetyLine,
		styles.detailSection.Render("Actions"),
		actionLine,
		actionSafety,
		styles.helpAction.Render("Other: / filter, r reconnect, q quit"),
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
	if m.statusError {
		return truncate(styles.statusError.Render(line), maxInt(m.width, 40))
	}
	return truncate(styles.statusNormal.Render(line), maxInt(m.width, 40))
}

func (m model) renderHelp() string {
	segments := []string{
		m.helpSegment("/", "filter"),
		m.helpSegment("↑↓", "move"),
		m.helpSegment("1-5", "chips"),
	}

	if m.sinkInFlight {
		segments = append(segments, styles.helpAction.Render("sink in progress..."))
	} else if selected, ok := m.currentListener(); ok && listenerRequiresAdmin(selected) {
		segments = append(segments, m.helpSegment("k/K", "disabled (admin required)"))
	} else {
		segments = append(segments, m.helpSegment("k", "term"), m.helpSegmentDanger("✕K", "force"))
	}

	segments = append(
		segments,
		m.helpSegment("r", "reconnect"),
		m.helpSegment("Esc", "clear"),
		m.helpSegment("q", "quit"),
	)

	line := strings.Join(segments, styles.helpSeparator.Render(" · "))
	return truncate(line, maxInt(m.width, 40))
}

func (m model) renderListControlChips(contentWidth int) string {
	filterChip := func(mode listFilterMode, label string) string {
		if m.listFilter == mode {
			return styles.chipActive.Render(label)
		}
		return styles.chipIdle.Render(label)
	}

	quickFilterLabel := "All"
	switch m.listFilter {
	case listFilterIPv4:
		quickFilterLabel = "IPv4"
	case listFilterIPv6:
		quickFilterLabel = "IPv6"
	case listFilterWildcard:
		quickFilterLabel = "Wildcard"
	case listFilterUserOwned:
		quickFilterLabel = "User-owned"
	}
	filterSummary := styles.chipIdle.Render("Filter: " + quickFilterLabel)
	if strings.TrimSpace(m.filter) != "" {
		filterSummary = styles.chipActive.Render("Filter: " + m.filter + " + " + quickFilterLabel)
	}

	line := lipgloss.JoinHorizontal(
		lipgloss.Top,
		styles.chipIdle.Render("Sort:"),
		styles.chipActive.Render("Port"),
		filterSummary,
		filterChip(listFilterAll, "All"),
		filterChip(listFilterIPv4, "IPv4"),
		filterChip(listFilterIPv6, "IPv6"),
		filterChip(listFilterWildcard, "Wildcard"),
		filterChip(listFilterUserOwned, "User-owned"),
	)
	return truncate(line, contentWidth)
}

func (m model) helpSegment(key string, action string) string {
	return lipgloss.JoinHorizontal(
		lipgloss.Top,
		styles.helpKey.Render(key),
		styles.helpAction.Render(action),
	)
}

func (m model) helpSegmentDanger(key string, action string) string {
	return lipgloss.JoinHorizontal(
		lipgloss.Top,
		styles.helpDangerKey.Render(key),
		styles.helpAction.Render(action),
	)
}

func (m model) detailMetricLine(label string, value string) string {
	return lipgloss.JoinHorizontal(
		lipgloss.Top,
		styles.helpKey.Render(label),
		styles.detailBody.Render(value),
	)
}

func compactPath(path string, width int) string {
	trimmed := strings.TrimSpace(path)
	if trimmed == "" || trimmed == "-" {
		return "-"
	}
	if width <= 0 {
		return trimmed
	}
	if runeLen(trimmed) <= width {
		return trimmed
	}
	parts := strings.Split(trimmed, "/")
	filtered := make([]string, 0, len(parts))
	for _, part := range parts {
		if part != "" {
			filtered = append(filtered, part)
		}
	}
	if len(filtered) == 0 {
		return truncate(trimmed, width)
	}
	if len(filtered) == 1 {
		return truncate("…/"+filtered[0], width)
	}

	candidate := "…/" + filtered[len(filtered)-2] + "/" + filtered[len(filtered)-1]
	if runeLen(candidate) <= width {
		return candidate
	}

	return truncate(candidate, width)
}

func bindClassification(bindAddress string) string {
	address := strings.TrimSpace(strings.ToLower(bindAddress))
	switch address {
	case "", "*", "0.0.0.0", "::", "[::]":
		return "wildcard"
	case "localhost", "::1":
		return "localhost"
	}

	if strings.HasPrefix(address, "127.") {
		return "localhost"
	}

	return "other"
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
