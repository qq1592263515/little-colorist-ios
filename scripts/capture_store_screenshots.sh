#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NODE_BINARY="${NODE_BINARY:-}"

if [[ -z "$NODE_BINARY" ]]; then
  if command -v node >/dev/null 2>&1; then
    NODE_BINARY="$(command -v node)"
  else
    NODE_BINARY="/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node"
  fi
fi

mkdir -p "$ROOT/AppStore/Screenshots"
"$NODE_BINARY" "$ROOT/scripts/capture_store_screenshots.mjs"
