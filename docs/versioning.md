# Harbor Versioning and Release Policy

## Version policy

- Harbor uses repository-wide Semantic Versioning tags: `vX.Y.Z`.
- One version applies to Harbor CLI, macOS app, and Harbor TUI.
- Release automation updates `version.txt`, Xcode `MARKETING_VERSION`, Harbor CLI version, and Harbor TUI version together.
- Patch support policy: only the latest minor line is supported.

## Commit-to-version mapping

- `fix:` -> patch bump.
- `feat:` -> minor bump.
- `!` or `BREAKING CHANGE:` -> major bump.

## Schema compatibility

- `schemaVersion` is the machine-output contract version for JSON/JSONL payloads.
- Breaking wire-format changes require bumping `schemaVersion` and a major SemVer bump.
- Non-breaking additive changes should not bump `schemaVersion`.

## Release workflows

### Prepare release PR (manual)

Workflow: `.github/workflows/prepare-release.yml`

- Trigger: `workflow_dispatch` only.
- Behavior: runs `release-please` with `skip-github-release: true` using `RELEASE_PLEASE_TOKEN`.
- Outcome: opens/updates one release PR when maintainers request it.

### Publish release (on release PR merge)

Workflow: `.github/workflows/publish-release.yml`

- Trigger: merged PRs into `main`.
- Guard: runs only for merged release-please PRs (release-please branch + release title).
- Behavior: runs `release-please` with `skip-github-pull-request: true` using `RELEASE_PLEASE_TOKEN`.
- Outcome: creates the tag and GitHub Release; does not open a new release PR.

### Publish assets (on GitHub Release publish)

Workflow: `.github/workflows/publish-assets.yml`

- Trigger: published GitHub Release, plus manual `workflow_dispatch` reruns by tag.
- Behavior: builds CLI, TUI, and menubar app archives, uploads them to the release, and updates the Homebrew tap.
- Outcome: release assets become installable from Homebrew-backed URLs and a tap PR is opened when credentials are available.

## Maintainer flow

1. Merge feature/fix PRs into `main` as usual.
2. When ready to release, manually run `prepare-release`.
3. Review the generated release PR (version/changelog).
4. Merge the release PR.
5. Confirm `publish-release` created tag + GitHub Release.
6. Confirm `publish-assets` uploaded archives and opened the tap PR.
7. Merge the tap PR.

