#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/archive/小小涂色家.app}"
OUTPUT="${2:-$ROOT/build/app-store/小小涂色家.pkg}"
APP_IDENTITY="${APPLE_APP_IDENTITY:-3rd Party Mac Developer Application: JIAHUI CHEN (TX65SX7Y23)}"
INSTALLER_IDENTITY="${APPLE_INSTALLER_IDENTITY:-3rd Party Mac Developer Installer: JIAHUI CHEN (TX65SX7Y23)}"
PROFILE="${MAC_APP_PROVISIONING_PROFILE:-}"

if [[ ! -d "$APP" ]]; then
  echo "Missing app bundle: $APP" >&2
  exit 1
fi

if [[ -z "$PROFILE" ]]; then
  echo "Set MAC_APP_PROVISIONING_PROFILE to the Mac App Store profile." >&2
  exit 1
fi

if [[ ! -f "$PROFILE" ]]; then
  echo "Missing provisioning profile: $PROFILE" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
STAGED="$(mktemp -d)"
trap 'rm -rf "$STAGED"' EXIT
ditto "$APP" "$STAGED/小小涂色家.app"
APP="$STAGED/小小涂色家.app"

cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
security cms -D -i "$PROFILE" > "$STAGED/profile.plist"
plutil -extract Entitlements xml1 -o "$STAGED/app.entitlements" "$STAGED/profile.plist"
/usr/libexec/PlistBuddy -c "Add :com.apple.security.app-sandbox bool true" "$STAGED/app.entitlements"
/usr/libexec/PlistBuddy -c "Add :com.apple.security.files.user-selected.read-write bool true" "$STAGED/app.entitlements"

codesign \
  --force \
  --sign "$APP_IDENTITY" \
  --entitlements "$STAGED/app.entitlements" \
  --options runtime \
  --timestamp \
  "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"

productbuild \
  --component "$APP" /Applications \
  --sign "$INSTALLER_IDENTITY" \
  "$OUTPUT"

pkgutil --check-signature "$OUTPUT"
echo "Built: $OUTPUT"
