# Harbor Distribution

Harbor ships its release assets from GitHub Releases and updates the Homebrew tap from those same assets.

## Install paths

Primary install path:

```sh
brew tap VishalBilagi/tap
brew install VishalBilagi/tap/harbor
brew install VishalBilagi/tap/harbor-tui
brew install --cask VishalBilagi/tap/harbor-app
```

Direct download fallback:

- Release page: [https://github.com/VishalBilagi/harbor/releases](https://github.com/VishalBilagi/harbor/releases)
- CLI archives:
  - `harbor-vX.Y.Z-darwin-arm64.tar.gz`
  - `harbor-vX.Y.Z-darwin-amd64.tar.gz`
- TUI archives:
  - `harbor-tui-vX.Y.Z-darwin-arm64.tar.gz`
  - `harbor-tui-vX.Y.Z-darwin-amd64.tar.gz`
- App archive:
  - `Harbor-vX.Y.Z-macos.zip`

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

- Triggers:
  - published GitHub Release
  - manual `workflow_dispatch` with a `tag` input for reruns
- Build host: `macos-15`
- Responsibilities:
  - build CLI binaries for `arm64` and `x86_64`
  - build TUI binaries for `arm64` and `amd64`
  - build a universal menubar app archive
  - upload release assets
  - render tap files and open a PR against `VishalBilagi/homebrew-tap`

## Secrets

Required in the `harbor` repo:

- `RELEASE_PLEASE_TOKEN`
  - used by `prepare-release` and `publish-release`
  - fine-grained token for `VishalBilagi/harbor`
  - permissions:
    - `Contents`: read and write
    - `Pull requests`: read and write
    - `Issues`: read and write

- `HOMEBREW_TAP_PAT`
  - used by `publish-assets` to open PRs in `VishalBilagi/homebrew-tap`
  - fine-grained token for `VishalBilagi/homebrew-tap`
  - permissions:
    - `Contents`: read and write
    - `Pull requests`: read and write

Optional:

- `DEVELOPER_ID_APPLICATION`
  - used to sign the packaged app archive
  - if unset, the workflow falls back to ad-hoc signing for the app bundle

## Maintainer flow

1. Merge normal work into `main`.
2. Run `prepare-release`.
3. Merge the generated release PR.
4. Confirm `publish-release` created the GitHub Release.
5. Confirm `publish-assets` uploaded the archives and opened the tap PR.
6. Merge the tap PR in `VishalBilagi/homebrew-tap`.
7. Verify installs from the tap.

## Validation

After a successful release:

```sh
brew update
brew tap VishalBilagi/tap
brew install VishalBilagi/tap/harbor
brew install VishalBilagi/tap/harbor-tui
brew install --cask VishalBilagi/tap/harbor-app

harbor version
harbor list --json
harbor-tui --version
open -a Harbor
```

Asset integrity:

```sh
curl -LO https://github.com/VishalBilagi/harbor/releases/download/vX.Y.Z/checksums-vX.Y.Z.txt
shasum -a 256 --check checksums-vX.Y.Z.txt
```

Local tap-file validation:

```sh
brew audit --formula /path/to/homebrew-tap/Formula/harbor.rb
brew audit --formula /path/to/homebrew-tap/Formula/harbor-tui.rb
brew audit --cask /path/to/homebrew-tap/Casks/harbor-app.rb
brew test harbor
brew test harbor-tui
```

When proper signing/notarization is enabled, add Gatekeeper validation:

```sh
spctl --assess --type exec -vv /Applications/Harbor.app
```
