package main

import "testing"

func TestParseConfigSupportsVersionFlag(t *testing.T) {
	cfg, err := parseConfig([]string{"--version"})
	if err != nil {
		t.Fatalf("parseConfig returned error: %v", err)
	}

	if !cfg.showVersion {
		t.Fatalf("expected showVersion=true")
	}
}

func TestParseConfigRejectsNonPositiveInterval(t *testing.T) {
	_, err := parseConfig([]string{"--interval", "0"})
	if err == nil {
		t.Fatalf("expected interval validation error")
	}
}
