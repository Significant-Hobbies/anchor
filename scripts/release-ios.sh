#!/bin/bash
#
# Build an App Store-ready Anchor.ipa (iPhone app with the watch app embedded).
#
#   ./scripts/release-ios.sh
#   ./scripts/release-ios.sh --upload
#   ./scripts/release-ios.sh --upload-only
#   ./scripts/release-ios.sh --configure-upload
#
# Produces dist/Anchor-<version>-<build>.ipa, signed with the Apple Distribution
# certificate and a Store provisioning profile that carries the CloudKit
# container and the shared app group.
#
# The Mac direct-download and iPhone/Watch builds both keep iCloud. Each uses the
# appropriate provisioning profile for its distribution channel.
#
# Upload credentials stay in the macOS login Keychain. The script passes only
# an @keychain reference to Apple's uploader, never the password itself.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD_DIR="$ROOT/build/release-ios"
DIST="$ROOT/dist"
KEYCHAIN_SERVICE="${ANCHOR_APPSTORE_KEYCHAIN_SERVICE:-fleet-personal-appstore}"

VERSION=$(/usr/bin/awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' Apps/project.yml)
VERSION="${VERSION:-1.0}"
BUILD_NUMBER=$(/usr/bin/awk -F'"' '/CURRENT_PROJECT_VERSION/ {print $2; exit}' Apps/project.yml)
BUILD_NUMBER="${BUILD_NUMBER:-unknown}"
IPA="$DIST/Anchor-$VERSION-$BUILD_NUMBER.ipa"

usage() {
  cat <<USAGE
Usage: $0 [--upload | --upload-only | --configure-upload]

  (no option)          Build, export, and verify $IPA
  --upload             Build, export, verify, and upload to App Store Connect
  --upload-only        Upload the existing $IPA without rebuilding
  --configure-upload   Securely store or refresh $KEYCHAIN_SERVICE in Keychain

Set ANCHOR_APPSTORE_KEYCHAIN_SERVICE to use a different Keychain item.
USAGE
}

keychain_account() {
  security find-generic-password -s "$KEYCHAIN_SERVICE" 2>/dev/null \
    | /usr/bin/awk -F'"' '/"acct"/{print $4; exit}'
}

configure_upload() {
  local existing_account account
  existing_account="$(keychain_account || true)"
  if [ -n "$existing_account" ]; then
    read -r -p "Apple Account [$existing_account]: " account
    account="${account:-$existing_account}"
  else
    read -r -p "Apple Account: " account
  fi
  [ -n "$account" ] || { echo "✘ Apple Account is required." >&2; exit 1; }

  echo "Keychain will securely prompt for the new app-specific password."
  security add-generic-password -U \
    -a "$account" \
    -s "$KEYCHAIN_SERVICE" \
    -w
  echo "✅ Updated Keychain item: $KEYCHAIN_SERVICE"
}

upload_ipa() {
  local account
  [ -f "$IPA" ] || { echo "✘ Missing $IPA. Build it first." >&2; exit 1; }
  account="$(keychain_account || true)"
  if [ -z "$account" ]; then
    echo "✘ Keychain item '$KEYCHAIN_SERVICE' is not configured." >&2
    echo "  Run: $0 --configure-upload" >&2
    exit 1
  fi

  echo "==> Uploading build $BUILD_NUMBER to App Store Connect"
  xcrun altool --upload-app \
    --file "$IPA" \
    --type ios \
    --username "$account" \
    --password "@keychain:$KEYCHAIN_SERVICE" \
    --show-progress
}

ACTION="${1:-build}"
case "$ACTION" in
  build) ;;
  --upload) ACTION="upload" ;;
  --upload-only)
    upload_ipa
    exit 0
    ;;
  --configure-upload)
    configure_upload
    exit 0
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

echo "==> Anchor $VERSION — App Store build"

if ! security find-identity -p codesigning -v | grep -q "Apple Distribution"; then
  echo "✘ No 'Apple Distribution' certificate in the keychain." >&2
  exit 1
fi

command -v xcodegen >/dev/null && (cd Apps && xcodegen generate >/dev/null)

echo "==> Archiving (Release)"
if [ -e "$BUILD_DIR" ]; then
  PREVIOUS_BUILD_DIR="$BUILD_DIR.previous-$(date -u +%Y%m%dT%H%M%SZ)"
  mv "$BUILD_DIR" "$PREVIOUS_BUILD_DIR"
  echo "   preserved previous build at $PREVIOUS_BUILD_DIR"
fi
mkdir -p "$BUILD_DIR" "$DIST"
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
if [ -e "$IPA" ]; then
  PREVIOUS_IPA="$IPA.previous-$(date -u +%Y%m%dT%H%M%SZ)"
  mv "$IPA" "$PREVIOUS_IPA"
  echo "   preserved previous IPA at $PREVIOUS_IPA"
fi
cp "$BUILD_DIR/export/Anchor.ipa" "$IPA"

echo "==> Verifying"
UNZIP="$BUILD_DIR/verify"
mkdir -p "$UNZIP"
unzip -q "$IPA" -d "$UNZIP"
APP="$UNZIP/Payload/Anchor.app"

codesign -dvv "$APP" 2>&1 | grep -E "Authority=Apple Distribution|Identifier=" | head -2 | sed 's/^/   /'
if [ -d "$APP/Watch/Anchor.app" ]; then
  echo "   watch app: embedded"
else
  echo "✘ Watch app missing from the payload" >&2
  exit 1
fi

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
du -h "$IPA" | awk '{print "   " $1}'
if [ "$ACTION" = "upload" ]; then
  upload_ipa
else
  echo "   Upload with: $0 --upload-only"
fi
