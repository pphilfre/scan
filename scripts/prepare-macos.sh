#!/bin/bash
set -euo pipefail
# Match mail's pinned toolchain; no SDK or simulator downloads during a build.
sudo xcode-select --switch /Applications/Xcode_26.6.app/Contents/Developer
xcodebuild -version
if ! command -v xcodegen >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen
fi
xcodegen generate --spec project.yml
