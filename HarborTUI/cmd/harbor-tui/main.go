package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

type appConfig struct {
	harborBin   string
	interval    time.Duration
	altScreen   bool
	showVersion bool
}

var tuiVersion = "0.5.0" // x-release-please-version

func main() {
	cfg, err := parseConfig(os.Args[1:])
	if err != nil {
		fmt.Fprintf(os.Stderr, "harbor-tui: %v\n", err)
		os.Exit(2)
	}
	if cfg.showVersion {
		fmt.Println(tuiVersion)
		return
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

func parseConfig(args []string) (appConfig, error) {
	cfg := appConfig{}
	var intervalSeconds float64
	flagSet := flag.NewFlagSet("harbor-tui", flag.ContinueOnError)
	flagSet.SetOutput(io.Discard)

	flagSet.StringVar(&cfg.harborBin, "harbor-bin", "harbor", "Path to the harbor CLI binary")
	flagSet.Float64Var(&intervalSeconds, "interval", 2, "Refresh interval in seconds")
	flagSet.BoolVar(&cfg.altScreen, "alt-screen", true, "Use terminal alternate screen mode")
	flagSet.BoolVar(&cfg.showVersion, "version", false, "Print version and exit")
	if err := flagSet.Parse(args); err != nil {
		return cfg, err
	}

	if intervalSeconds <= 0 {
		return cfg, fmt.Errorf("interval must be greater than 0")
	}

	cfg.interval = time.Duration(intervalSeconds * float64(time.Second))
	return cfg, nil
}
