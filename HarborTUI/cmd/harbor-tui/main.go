package main

import (
	"flag"
	"fmt"
	"os"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

type appConfig struct {
	harborBin string
	interval  time.Duration
	altScreen bool
}

func main() {
	cfg, err := parseConfig()
	if err != nil {
		fmt.Fprintf(os.Stderr, "harbor-tui: %v\n", err)
		os.Exit(2)
	}

	events := make(chan tea.Msg, 256)
	source := newHarborDataSource(cfg.harborBin, cfg.interval, events)
	source.Start()
	defer source.Stop()

	model := newModel(cfg, source, events)
	programOptions := []tea.ProgramOption{}
	if cfg.altScreen {
		programOptions = append(programOptions, tea.WithAltScreen())
	}

	program := tea.NewProgram(model, programOptions...)
	if _, err := program.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "harbor-tui failed: %v\n", err)
		os.Exit(1)
	}
}

func parseConfig() (appConfig, error) {
	cfg := appConfig{}
	var intervalSeconds float64

	flag.StringVar(&cfg.harborBin, "harbor-bin", "harbor", "Path to the harbor CLI binary")
	flag.Float64Var(&intervalSeconds, "interval", 2, "Refresh interval in seconds")
	flag.BoolVar(&cfg.altScreen, "alt-screen", true, "Use terminal alternate screen mode")
	flag.Parse()

	if intervalSeconds <= 0 {
		return cfg, fmt.Errorf("interval must be greater than 0")
	}

	cfg.interval = time.Duration(intervalSeconds * float64(time.Second))
	return cfg, nil
}
