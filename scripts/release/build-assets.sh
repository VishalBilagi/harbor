#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <version> <output-dir>" >&2
  exit 1
fi

VERSION="$1"
OUTPUT_DIR="$2"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

CLI_ARM_DD="$OUTPUT_DIR/derived-cli-arm64"
CLI_X86_DD="$OUTPUT_DIR/derived-cli-x86_64"
APP_ARM_DD="$OUTPUT_DIR/derived-app-arm64"
APP_X86_DD="$OUTPUT_DIR/derived-app-x86_64"
TUI_OUT_DIR="$OUTPUT_DIR/tui"
STAGE_DIR="$OUTPUT_DIR/stage"

mkdir -p "$OUTPUT_DIR" "$TUI_OUT_DIR" "$STAGE_DIR"

build_cli() {
  local arch="$1"
  local derived_data="$2"
  xcodebuild \
    -project "$ROOT_DIR/Harbor.xcodeproj" \
    -scheme harbor \
    -configuration Release \
    -destination "platform=macOS,arch=$arch" \
    -derivedDataPath "$derived_data" \
    build
}

build_app() {
  local arch="$1"
  local derived_data="$2"
  xcodebuild \
    -project "$ROOT_DIR/Harbor.xcodeproj" \
    -scheme Harbor \
    -configuration Release \
    -destination "platform=macOS,arch=$arch" \
    -derivedDataPath "$derived_data" \
    build
}

package_tarball() {
  local archive_name="$1"
  local source_dir="$2"
  local binary_name="$3"
  tar -czf "$OUTPUT_DIR/$archive_name" -C "$source_dir" "$binary_name"
}

build_cli arm64 "$CLI_ARM_DD"
build_cli x86_64 "$CLI_X86_DD"

mkdir -p "$STAGE_DIR/cli-arm64" "$STAGE_DIR/cli-amd64"
cp "$CLI_ARM_DD/Build/Products/Release/harbor" "$STAGE_DIR/cli-arm64/harbor"
cp "$CLI_X86_DD/Build/Products/Release/harbor" "$STAGE_DIR/cli-amd64/harbor"
chmod +x "$STAGE_DIR/cli-arm64/harbor" "$STAGE_DIR/cli-amd64/harbor"

package_tarball "harbor-v${VERSION}-darwin-arm64.tar.gz" "$STAGE_DIR/cli-arm64" "harbor"
package_tarball "harbor-v${VERSION}-darwin-amd64.tar.gz" "$STAGE_DIR/cli-amd64" "harbor"

mkdir -p "$STAGE_DIR/tui-arm64" "$STAGE_DIR/tui-amd64"
(
  cd "$ROOT_DIR/HarborTUI"
  GOARCH=arm64 GOOS=darwin go build -o "$STAGE_DIR/tui-arm64/harbor-tui" ./cmd/harbor-tui
  GOARCH=amd64 GOOS=darwin go build -o "$STAGE_DIR/tui-amd64/harbor-tui" ./cmd/harbor-tui
)
chmod +x "$STAGE_DIR/tui-arm64/harbor-tui" "$STAGE_DIR/tui-amd64/harbor-tui"

package_tarball "harbor-tui-v${VERSION}-darwin-arm64.tar.gz" "$STAGE_DIR/tui-arm64" "harbor-tui"
package_tarball "harbor-tui-v${VERSION}-darwin-amd64.tar.gz" "$STAGE_DIR/tui-amd64" "harbor-tui"

build_app arm64 "$APP_ARM_DD"
build_app x86_64 "$APP_X86_DD"

rm -rf "$STAGE_DIR/Harbor.app"
cp -R "$APP_ARM_DD/Build/Products/Release/Harbor.app" "$STAGE_DIR/Harbor.app"
lipo -create \
  "$APP_ARM_DD/Build/Products/Release/Harbor.app/Contents/MacOS/Harbor" \
  "$APP_X86_DD/Build/Products/Release/Harbor.app/Contents/MacOS/Harbor" \
  -output "$STAGE_DIR/Harbor.app/Contents/MacOS/Harbor"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --deep --sign "$DEVELOPER_ID_APPLICATION" "$STAGE_DIR/Harbor.app"
else
  codesign --force --deep --sign - --timestamp=none "$STAGE_DIR/Harbor.app"
fi

ditto -c -k --keepParent "$STAGE_DIR/Harbor.app" "$OUTPUT_DIR/Harbor-v${VERSION}-macos.zip"

(
  cd "$OUTPUT_DIR"
  shasum -a 256 \
    "Harbor-v${VERSION}-macos.zip" \
    "harbor-v${VERSION}-darwin-arm64.tar.gz" \
    "harbor-v${VERSION}-darwin-amd64.tar.gz" \
    "harbor-tui-v${VERSION}-darwin-arm64.tar.gz" \
    "harbor-tui-v${VERSION}-darwin-amd64.tar.gz" \
    > "checksums-v${VERSION}.txt"
)
