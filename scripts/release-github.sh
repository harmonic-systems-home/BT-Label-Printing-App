#!/bin/bash
# Build the free edition of BTLabel for a GitHub release: the Release configuration
# (no APP_STORE flag -> unlimited printing, local storage, no iCloud), signed with
# Developer ID, notarized, and stapled.
#
# Output: build/github-release/BTLabel-<version>.zip  (attach it to a GitHub release)
#
# One-time setup — store notarization credentials in the keychain:
#   xcrun notarytool store-credentials BTLabel --apple-id <apple-id> --team-id 8H3FX5B8KD
# (use an app-specific password from account.apple.com). Override the profile name
# with NOTARY_PROFILE=...; set NOTARIZE=0 for an unsigned-by-Apple local dry run.
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID=8H3FX5B8KD
PROFILE="${NOTARY_PROFILE:-BTLabel}"
OUT=build/github-release
ARCHIVE="$OUT/BTLabel.xcarchive"
APP="$OUT/export/BTLabel.app"

rm -rf "$OUT"
mkdir -p "$OUT"

echo "==> Archiving (Release configuration)"
xcodebuild archive -quiet \
    -project BTLabel/BTLabel.xcodeproj -scheme BTLabel -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE"

cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF

echo "==> Exporting with Developer ID"
xcodebuild -exportArchive -quiet -allowProvisioningUpdates \
    -archivePath "$ARCHIVE" -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export"

# Guard against shipping the App Store edition by mistake.
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q icloud; then
    echo "error: $APP has iCloud entitlements — that is the App Store edition" >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")
ZIP="$OUT/BTLabel-$VERSION.zip"

if [[ "${NOTARIZE:-1}" != 0 ]]; then
    echo "==> Notarizing $VERSION ($BUILD)"
    ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
    xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$APP"
    rm "$OUT/notarize.zip"
    spctl --assess --type execute --verbose "$APP"
fi

ditto -c -k --keepParent "$APP" "$ZIP"
echo "==> $ZIP"
