# Harbor

Harbor is a local listening-port monitor for macOS. The repo is split into a shared Swift core, a Swift CLI, a SwiftUI app target, and a Go TUI module.

## Layout

- `Sources/PortKit`: shared Swift library used by the CLI and macOS app
- `Sources/harbor`: Swift CLI target
- `Harbor`: SwiftUI macOS app sources
- `Harbor.xcodeproj`: Xcode project for the macOS app
- `HarborTUI`: Go module for the terminal UI
- `Tests/PortKitTests`: Swift package tests for the shared core

## Build

### Swift package

```sh
swift build
```

### Swift package tests

```sh
swift test
```

### macOS app

```sh
xcodebuild -project Harbor.xcodeproj -scheme Harbor build
```

### Go TUI module

```sh
cd HarborTUI
go build ./...
```

## Notes

- `PortKit` is the shared source of truth for listener discovery and process metadata.
- The macOS app will consume `PortKit` directly.
- The Go TUI will consume machine-readable CLI output instead of reimplementing scanning logic.
