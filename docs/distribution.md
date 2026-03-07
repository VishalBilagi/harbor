# Harbor Distribution

Harbor ships its release assets from GitHub Releases and updates the Homebrew tap from those same assets.

## Release assets

Each release publishes:

- `Harbor-vX.Y.Z-macos.zip`
- `harbor-vX.Y.Z-darwin-arm64.tar.gz`
- `harbor-vX.Y.Z-darwin-amd64.tar.gz`
- `harbor-tui-vX.Y.Z-darwin-arm64.tar.gz`
- `harbor-tui-vX.Y.Z-darwin-amd64.tar.gz`
- `checksums-vX.Y.Z.txt`

## Automation

Workflow: `.github/workflows/publish-assets.yml`

- Trigger: published GitHub Release
- Build host: `macos-15`
- Responsibilities:
  - build CLI binaries for `arm64` and `x86_64`
  - build TUI binaries for `arm64` and `amd64`
  - build a universal menubar app archive
  - upload release assets
  - render tap files and open a PR against `VishalBilagi/homebrew-tap`

## Secrets

Optional:

- `DEVELOPER_ID_APPLICATION`

Required for tap update PRs:

- `HOMEBREW_TAP_PAT`

## Maintainer flow

1. Merge normal work into `main`.
2. Run `prepare-release`.
3. Merge the generated release PR.
4. Confirm `publish-release` created the GitHub Release.
5. Confirm `publish-assets` uploaded the archives and opened the tap PR.
