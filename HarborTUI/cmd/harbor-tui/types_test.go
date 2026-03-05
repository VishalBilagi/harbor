package main

import "testing"

func TestSortedListenersOrdersByPortPIDAndFamily(t *testing.T) {
	listeners := []listenerRecord{
		{Port: 8080, PID: 200, Family: "ipv6", BindAddress: "::1"},
		{Port: 3000, PID: 400, Family: "ipv4", BindAddress: "127.0.0.1"},
		{Port: 3000, PID: 100, Family: "ipv6", BindAddress: "::1"},
		{Port: 3000, PID: 100, Family: "ipv4", BindAddress: "127.0.0.1"},
	}

	sorted := sortedListeners(listeners)
	if len(sorted) != 4 {
		t.Fatalf("expected 4 listeners, got %d", len(sorted))
	}

	if sorted[0].Port != 3000 || sorted[0].PID != 100 || sorted[0].Family != "ipv4" {
		t.Fatalf("unexpected first row: %+v", sorted[0])
	}
	if sorted[1].Port != 3000 || sorted[1].PID != 100 || sorted[1].Family != "ipv6" {
		t.Fatalf("unexpected second row: %+v", sorted[1])
	}
	if sorted[2].Port != 3000 || sorted[2].PID != 400 {
		t.Fatalf("unexpected third row: %+v", sorted[2])
	}
	if sorted[3].Port != 8080 || sorted[3].PID != 200 {
		t.Fatalf("unexpected fourth row: %+v", sorted[3])
	}
}

func TestApplyFilterMatchesPortProcessCmdAndCwd(t *testing.T) {
	cmd := "node /srv/api/server.js"
	cwd := "/Users/dev/api"
	listeners := []listenerRecord{
		{Port: 3000, PID: 111, ProcessName: "node", CommandLine: &cmd, Cwd: &cwd},
		{Port: 5432, PID: 222, ProcessName: "postgres"},
	}

	cases := []struct {
		query string
		want  int
	}{
		{query: "3000", want: 1},
		{query: "node", want: 1},
		{query: "server.js", want: 1},
		{query: "/users/dev", want: 1},
		{query: "postgres", want: 1},
		{query: "missing", want: 0},
	}

	for _, testCase := range cases {
		got := applyFilter(listeners, testCase.query)
		if len(got) != testCase.want {
			t.Fatalf("query %q expected %d matches, got %d", testCase.query, testCase.want, len(got))
		}
	}
}
