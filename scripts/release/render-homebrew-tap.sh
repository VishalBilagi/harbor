#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <version> <dist-dir> <tap-dir>" >&2
  exit 1
fi

VERSION="$1"
DIST_DIR="$2"
TAP_DIR="$3"
CHECKSUMS_FILE="$DIST_DIR/checksums-v${VERSION}.txt"

sha_for() {
  local file_name="$1"
  awk -v target="$file_name" '$2 ~ target { print $1 }' "$CHECKSUMS_FILE"
}

CLI_ARM_SHA="$(sha_for "harbor-v${VERSION}-darwin-arm64.tar.gz")"
CLI_AMD_SHA="$(sha_for "harbor-v${VERSION}-darwin-amd64.tar.gz")"
TUI_ARM_SHA="$(sha_for "harbor-tui-v${VERSION}-darwin-arm64.tar.gz")"
TUI_AMD_SHA="$(sha_for "harbor-tui-v${VERSION}-darwin-amd64.tar.gz")"
APP_SHA="$(sha_for "Harbor-v${VERSION}-macos.zip")"

mkdir -p "$TAP_DIR/Formula" "$TAP_DIR/Casks"

cat > "$TAP_DIR/Formula/harbor.rb" <<EOF
class Harbor < Formula
  desc "Local listening-port monitor for macOS"
  homepage "https://github.com/VishalBilagi/harbor"
  version "${VERSION}"

  on_arm do
    url "https://github.com/VishalBilagi/harbor/releases/download/v#{version}/harbor-v#{version}-darwin-arm64.tar.gz"
    sha256 "${CLI_ARM_SHA}"
  end

  on_intel do
    url "https://github.com/VishalBilagi/harbor/releases/download/v#{version}/harbor-v#{version}-darwin-amd64.tar.gz"
    sha256 "${CLI_AMD_SHA}"
  end

  def install
    bin.install "harbor"
  end

  test do
    output = shell_output("#{bin}/harbor version").strip
    assert_equal version.to_s, output
  end
end
EOF

cat > "$TAP_DIR/Formula/harbor-tui.rb" <<EOF
class HarborTui < Formula
  desc "Terminal UI for Harbor"
  homepage "https://github.com/VishalBilagi/harbor"
  version "${VERSION}"
  depends_on "harbor"

  on_arm do
    url "https://github.com/VishalBilagi/harbor/releases/download/v#{version}/harbor-tui-v#{version}-darwin-arm64.tar.gz"
    sha256 "${TUI_ARM_SHA}"
  end

  on_intel do
    url "https://github.com/VishalBilagi/harbor/releases/download/v#{version}/harbor-tui-v#{version}-darwin-amd64.tar.gz"
    sha256 "${TUI_AMD_SHA}"
  end

  def install
    bin.install "harbor-tui"
  end

  test do
    output = shell_output("#{bin}/harbor-tui --version").strip
    assert_equal version.to_s, output
  end
end
EOF

cat > "$TAP_DIR/Casks/harbor-app.rb" <<EOF
cask "harbor-app" do
  version "${VERSION}"
  sha256 "${APP_SHA}"

  url "https://github.com/VishalBilagi/harbor/releases/download/v#{version}/Harbor-v#{version}-macos.zip"
  name "Harbor"
  desc "Local listening-port monitor for macOS"
  homepage "https://github.com/VishalBilagi/harbor"

  app "Harbor.app"
end
EOF
