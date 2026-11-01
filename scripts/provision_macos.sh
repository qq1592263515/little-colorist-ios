#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/appstore_env.sh"

IDENTIFIER="com.jiahuichen.littlecolorist"
PROFILE_PATH="$ROOT/AppStore/LittleColorist-Mac-App-Store.provisionprofile"

ruby "$ROOT/scripts/asc.rb" check
ruby "$ROOT/scripts/asc.rb" ensure-bundle-id "$IDENTIFIER" "Little Colorist"
ruby "$ROOT/scripts/asc.rb" create-profile \
  "$IDENTIFIER" \
  "Little Colorist Mac App Store" \
  "$PROFILE_PATH"

security cms -D -i "$PROFILE_PATH" >/dev/null
echo "Provisioning profile ready: $PROFILE_PATH"
