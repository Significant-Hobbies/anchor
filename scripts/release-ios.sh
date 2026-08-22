#!/bin/bash
#
# Build an App Store-ready Anchor.ipa (iPhone app with the watch app embedded).
#
#   ./scripts/release-ios.sh
#
# Produces dist/Anchor-<version>.ipa, signed with the Apple Distribution
# certificate and a Store provisioning profile that carries the CloudKit
# container and the shared app group.
#
# The Mac direct-download and iPhone/Watch builds both keep iCloud. Each uses the
# appropriate provisioning profile for its distribution channel.
#
# Uploading needs App Store Connect credentials, which this repo does not carry:
#
#   xcrun altool --upload-app -f dist/Anchor-<version>.ipa -t ios \
#     --apple-id "<your-apple-id>" --password "<app-specific-password>"
#
# or drag the .ipa into Transporter.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD_DIR="$ROOT/build/release-ios"
DIST="$ROOT/dist"

VERSION=$(/usr/bin/awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' Apps/project.yml)
VERSION="${VERSION:-1.0}"
IPA="$DIST/Anchor-$VERSION.ipa"

echo "==> Anchor $VERSION — App Store build"

if ! security find-identity -p codesigning -v | grep -q "Apple Distribution"; then
  echo "✘ No 'Apple Distribution' certificate in the keychain." >&2
  exit 1
fi

command -v xcodegen >/dev/null && (cd Apps && xcodegen generate >/dev/null)

echo "==> Archiving (Release)"
rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR" "$DIST"
ARCHIVE="$BUILD_DIR/Anchor.xcarchive"
xcodebuild archive -project Apps/Anchor.xcodeproj \
  -scheme "Anchor (iOS)" \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$BUILD_DIR/dd" \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates | grep -E "error:|ARCHIVE SUCCEEDED|ARCHIVE FAILED" || true
[ -d "$ARCHIVE" ] || { echo "✘ Archive failed" >&2; exit 1; }

echo "==> Exporting (app-store-connect)"
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>export</string>
	<key>signingStyle</key><string>automatic</string>
	<key>teamID</key><string>8F7LXHTJZR</string>
	<key>uploadSymbols</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportPath "$BUILD_DIR/export" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -allowProvisioningUpdates | grep -E "error:|EXPORT SUCCEEDED|EXPORT FAILED" || true

[ -f "$BUILD_DIR/export/Anchor.ipa" ] || { echo "✘ Export produced no .ipa" >&2; exit 1; }
cp "$BUILD_DIR/export/Anchor.ipa" "$IPA"

echo "==> Verifying"
UNZIP="$BUILD_DIR/verify"
rm -rf "$UNZIP" && mkdir -p "$UNZIP"
unzip -q "$IPA" -d "$UNZIP"
APP="$UNZIP/Payload/Anchor.app"

codesign -dvv "$APP" 2>&1 | grep -E "Authority=Apple Distribution|Identifier=" | head -2 | sed 's/^/   /'
[ -d "$APP/Watch/Anchor.app" ] && echo "   watch app: embedded" || { echo "✘ Watch app missing from the payload" >&2; exit 1; }

# The App Store build must keep CloudKit and must not ship a debug entitlement.
codesign -d --entitlements :- "$APP" 2>/dev/null | python3 -c '
import sys, plistlib
raw = sys.stdin.buffer.read()
start = raw.find(b"<?xml")
e = plistlib.loads(raw[start:]) if start >= 0 else {}
problems = []
if not e.get("com.apple.developer.icloud-services"): problems.append("iCloud services missing")
if not e.get("com.apple.developer.icloud-container-identifiers"): problems.append("iCloud container missing")
if not e.get("com.apple.security.application-groups"): problems.append("app group missing")
if e.get("get-task-allow"): problems.append("get-task-allow is true")
for p in problems: print("   x", p)
env = e.get("com.apple.developer.icloud-container-environment", "unset")
print("   iCloud environment:", env)
if not problems: print("   entitlements: ok")
sys.exit(1 if problems else 0)
'

echo
echo "✅ $IPA"
ls -lh "$IPA" | awk '{print "   " $5}'
echo "   Upload with Transporter, or xcrun altool --upload-app (needs your Apple ID)."
