#!/bin/bash
#
# Build a signed, notarisable Anchor.dmg for direct download.
#
#   ./scripts/release-mac.sh
#
# Produces dist/Anchor-<version>-<build>.dmg, signed with the Developer ID certificate
# and built with the hardened runtime, which is what notarisation requires.
#
# Notarisation is opt-in because it needs credentials this repo does not carry.
# Create them once:
#
#   xcrun notarytool store-credentials "anchor-notary" \
#     --apple-id "<your-apple-id>" --team-id 8F7LXHTJZR \
#     --password "<app-specific-password from appleid.apple.com>"
#
# then re-run with ANCHOR_NOTARY_PROFILE=anchor-notary to notarise and staple.
#
# iCloud and app groups are restricted entitlements. `ReleaseDirect` pairs them
# with the installed `Anchor Developer ID` provisioning profile so the normal
# direct-download app uses the same production CloudKit container as iPhone and
# Watch.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
CONFIG="ReleaseDirect"
IDENTITY="Developer ID Application"
BUILD_DIR="$ROOT/build/release-mac"
DIST="$ROOT/dist"
STAGE="$BUILD_DIR/stage"

VERSION=$(/usr/bin/awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' Apps/project.yml)
VERSION="${VERSION:-1.0}"
BUILD_NUMBER=$(/usr/bin/awk -F'"' '/CURRENT_PROJECT_VERSION/ {print $2; exit}' Apps/project.yml)
BUILD_NUMBER="${BUILD_NUMBER:-unknown}"
DMG="$DIST/Anchor-$VERSION-$BUILD_NUMBER.dmg"

echo "==> Anchor $VERSION — direct-download release"

if ! security find-identity -p codesigning -v | grep -q "$IDENTITY"; then
  echo "✘ No '$IDENTITY' certificate in the keychain." >&2
  echo "  Create one at https://developer.apple.com/account/resources/certificates" >&2
  exit 1
fi

command -v xcodegen >/dev/null && (cd Apps && xcodegen generate >/dev/null)

# Archive + export, not a plain `build`: a plain build injects the
# `com.apple.security.get-task-allow` debug entitlement, and notarisation
# rejects any app carrying it.
echo "==> Archiving ($CONFIG)"
if [ -e "$BUILD_DIR" ]; then
  PREVIOUS_BUILD_DIR="$BUILD_DIR.previous-$(date -u +%Y%m%dT%H%M%SZ)"
  mv "$BUILD_DIR" "$PREVIOUS_BUILD_DIR"
  echo "   preserved previous build at $PREVIOUS_BUILD_DIR"
fi
mkdir -p "$STAGE" "$DIST"
ARCHIVE="$BUILD_DIR/Anchor.xcarchive"
xcodebuild archive -project Apps/Anchor.xcodeproj \
  -scheme "Anchor (macOS)" \
  -configuration "$CONFIG" \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$BUILD_DIR/dd" \
  -destination 'generic/platform=macOS' | grep -E "error:|ARCHIVE SUCCEEDED|ARCHIVE FAILED" || true
[ -d "$ARCHIVE" ] || { echo "✘ Archive failed" >&2; exit 1; }

echo "==> Exporting (developer-id)"
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>destination</key><string>export</string>
	<key>method</key><string>developer-id</string>
	<key>signingStyle</key><string>manual</string>
	<key>teamID</key><string>8F7LXHTJZR</string>
	<key>provisioningProfiles</key>
	<dict>
		<key>com.significanthobbies.anchor</key><string>Anchor Developer ID</string>
	</dict>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportPath "$BUILD_DIR/export" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" | grep -E "error:|EXPORT SUCCEEDED|EXPORT FAILED" || true

APP="$BUILD_DIR/export/Anchor.app"
[ -d "$APP" ] || { echo "✘ Export produced no app at $APP" >&2; exit 1; }

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=1 "$APP" 2>&1 | tail -2
codesign -dvv "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier=" | head -4
# Hardened runtime shows as the "runtime" flag; notarisation refuses without it.
# Captured to a variable rather than piped into `grep -q`: under `pipefail` the
# early exit of grep -q SIGPIPEs codesign and the whole pipeline reads as failed.
SIGN_INFO=$(codesign -d --verbose=2 "$APP" 2>&1 || true)
if printf '%s' "$SIGN_INFO" | grep -qE "flags=.*runtime"; then
  echo "   hardened runtime: on"
else
  echo "✘ Hardened runtime missing — notarisation would reject this." >&2
  exit 1
fi

# get-task-allow is a debug entitlement; notarisation refuses anything carrying it.
# Checked by value, not by substring: `get-task-allow = false` is legitimate and a
# naive grep would reject a perfectly good build.
if ! codesign -d --entitlements :- "$APP" 2>/dev/null | python3 -c '
import sys, plistlib
raw = sys.stdin.buffer.read()
start = raw.find(b"<?xml")
entitlements = plistlib.loads(raw[start:]) if start >= 0 else {}
sys.exit(1 if any(entitlements.get(key) for key in (
    "get-task-allow", "com.apple.security.get-task-allow"
)) else 0)
'; then
  echo "✘ get-task-allow is true — notarisation would reject this." >&2
  exit 1
fi
echo "   debug entitlements: none"

# Direct distribution must keep production CloudKit; otherwise the Mac and
# TestFlight Watch silently operate on different stores.
codesign -d --entitlements :- "$APP" 2>/dev/null | python3 -c '
import sys, plistlib
raw = sys.stdin.buffer.read()
start = raw.find(b"<?xml")
e = plistlib.loads(raw[start:]) if start >= 0 else {}
problems = []
if not e.get("com.apple.developer.icloud-services"): problems.append("iCloud services missing")
if e.get("com.apple.developer.icloud-container-environment") != "Production":
    problems.append("Production iCloud environment missing")
if "iCloud.com.significanthobbies.anchor" not in e.get("com.apple.developer.icloud-container-identifiers", []):
    problems.append("Anchor iCloud container missing")
if not e.get("com.apple.security.application-groups"): problems.append("app group missing")
for problem in problems: print("   x", problem)
if not problems: print("   production CloudKit entitlements: ok")
sys.exit(1 if problems else 0)
'

echo "==> Packaging DMG"
cp -R "$APP" "$STAGE/Anchor.app"
ln -s /Applications "$STAGE/Applications"
if [ -e "$DMG" ]; then
  PREVIOUS_DMG="$DMG.previous-$(date -u +%Y%m%dT%H%M%SZ)"
  mv "$DMG" "$PREVIOUS_DMG"
  echo "   preserved previous DMG at $PREVIOUS_DMG"
fi
hdiutil create -volname "Anchor" -srcfolder "$STAGE" -ov -format UDZO "$DMG" | tail -1

echo "==> Signing DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
codesign --verify --verbose=1 "$DMG" 2>&1 | tail -1

if [ -n "${ANCHOR_NOTARY_PROFILE:-}" ]; then
  echo "==> Notarising as '$ANCHOR_NOTARY_PROFILE' (this takes a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$ANCHOR_NOTARY_PROFILE" --wait
  echo "==> Stapling"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl -a -t open --context context:primary-signature -v "$DMG" 2>&1 | tail -2
else
  echo "==> Skipping notarisation (ANCHOR_NOTARY_PROFILE unset)"
  echo "    The DMG is signed but not notarised: Gatekeeper will warn on other Macs."
fi

echo
echo "✅ $DMG"
ls -lh "$DMG" | awk '{print "   " $5}'
