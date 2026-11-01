#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
OUTPUT="$ROOT/build/local"
APP="$OUTPUT/小小涂色家.app"
EXECUTABLE="LittleColorist"
SOURCES=("$ROOT"/LittleColorist/App/*.swift)
SWIFT_FLAGS=(-swift-version 5 -parse-as-library -O -sdk "$SDK")

mkdir -p "$OUTPUT" "$OUTPUT/bin"

for ARCH in x86_64 arm64; do
  xcrun swiftc \
    "${SWIFT_FLAGS[@]}" \
    -target "$ARCH-apple-macos13.0" \
    -framework AppKit \
    -framework SwiftUI \
    -framework WebKit \
    -framework UniformTypeIdentifiers \
    -o "$OUTPUT/bin/$EXECUTABLE-$ARCH" \
    "${SOURCES[@]}"
done

lipo -create \
  "$OUTPUT/bin/$EXECUTABLE-x86_64" \
  "$OUTPUT/bin/$EXECUTABLE-arm64" \
  -output "$OUTPUT/bin/$EXECUTABLE"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUTPUT/bin/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"

plutil -create xml1 "$APP/Contents/Info.plist"
plutil -insert CFBundleDevelopmentRegion -string zh_CN "$APP/Contents/Info.plist"
plutil -insert CFBundleDisplayName -string "小小涂色家" "$APP/Contents/Info.plist"
plutil -insert CFBundleExecutable -string "$EXECUTABLE" "$APP/Contents/Info.plist"
plutil -insert CFBundleIconFile -string AppIcon "$APP/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string com.jiahuichen.littlecolorist "$APP/Contents/Info.plist"
plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$APP/Contents/Info.plist"
plutil -insert CFBundleName -string "小小涂色家" "$APP/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$APP/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string 1.0 "$APP/Contents/Info.plist"
plutil -insert CFBundleVersion -string 1 "$APP/Contents/Info.plist"
plutil -insert ITSAppUsesNonExemptEncryption -bool NO "$APP/Contents/Info.plist"
plutil -insert LSApplicationCategoryType -string public.app-category.games "$APP/Contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string 13.0 "$APP/Contents/Info.plist"
plutil -insert LSMultipleInstancesProhibited -bool YES "$APP/Contents/Info.plist"
plutil -insert NSHighResolutionCapable -bool YES "$APP/Contents/Info.plist"
plutil -insert NSSupportsAutomaticGraphicsSwitching -bool YES "$APP/Contents/Info.plist"
plutil -insert NSHumanReadableCopyright -string "Copyright © 2026 JIAHUI CHEN. All rights reserved." "$APP/Contents/Info.plist"

cp "$ROOT/LittleColorist/Resources/index.html" "$APP/Contents/Resources/index.html"
cp "$ROOT/LittleColorist/Resources/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$ROOT/LittleColorist/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

codesign \
  --force \
  --sign - \
  --timestamp=none \
  "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built: $APP"
