#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

plutil -lint \
  "$ROOT/LittleColorist/Resources/PrivacyInfo.xcprivacy" \
  "$ROOT/LittleColorist/Config/LittleColorist-macOS.entitlements"

if rg -n 'https?://(?!www\.w3\.org|react\.dev)' \
  "$ROOT/LittleColorist/Resources/index.html" \
  --pcre2 >/dev/null; then
  echo "Unexpected network URL found in offline game resource." >&2
  exit 1
fi

if [[ -d "$ROOT/LittleColorist.xcodeproj" ]]; then
  echo "Xcode project present."
fi

echo "Static validation passed."
