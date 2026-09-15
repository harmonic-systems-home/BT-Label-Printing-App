#!/bin/bash
# Archive, export, and (optionally) upload the App Store edition of BTLabel.
#
#   scripts/release-appstore.sh            # archive + export the .pkg only
#   scripts/release-appstore.sh --upload   # also upload to App Store Connect
#
# Uses the AppStore build configuration, so the build has the APP_STORE flag (print
# trial + in-app purchase) and the iCloud entitlements. The free GitHub edition is
# built by release-github.sh instead.
#
# Signing uses an App Store Connect API key, which lets xcodebuild create and renew
# the distribution certificate and provisioning profile headlessly — no Apple account
# needs to be signed in to Xcode (Xcode's Organizer fails with "App Store Connect
# access is required" when it isn't). Credentials come from
# ~/.appstoreconnect/credentials.env, which sets:
#   ASC_KEY_ID     Key ID, e.g. XKSRLQ7SB8 (must be an Admin or App Manager key —
#                  a Developer-role key can't use cloud-managed distribution certs)
#   ASC_ISSUER_ID  Issuer ID (App Store Connect -> Users and Access -> Integrations)
#   ASC_KEY_PATH   Path to AuthKey_<ASC_KEY_ID>.p8
#
# Bump MARKETING_VERSION / CURRENT_PROJECT_VERSION before running: App Store Connect
# rejects a build number it has already seen.
set -euo pipefail
cd "$(dirname "$0")/.."

UPLOAD=false
for arg in "$@"; do [ "$arg" = "--upload" ] && UPLOAD=true; done

CREDS="$HOME/.appstoreconnect/credentials.env"
[ -f "$CREDS" ] && { set -a; . "$CREDS"; set +a; }
: "${ASC_KEY_ID:?set ASC_KEY_ID (or create ~/.appstoreconnect/credentials.env)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
: "${ASC_KEY_PATH:?set ASC_KEY_PATH (path to AuthKey_*.p8)}"

TEAM_ID=8H3FX5B8KD
OUT=build/appstore
ARCHIVE="$OUT/BTLabel.xcarchive"
AUTH=(-authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" -authenticationKeyPath "$ASC_KEY_PATH")

rm -rf "$OUT"
mkdir -p "$OUT"

echo "==> Archiving (AppStore configuration)"
xcodebuild archive -quiet -allowProvisioningUpdates "${AUTH[@]}" \
    -project BTLabel/BTLabel.xcodeproj -scheme BTLabel -configuration AppStore \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE"

APP="$ARCHIVE/Products/Applications/BTLabel.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")

# Guard: the App Store edition must carry the iCloud entitlements. Without them this
# is the free edition, which would ship a paid app with no sync and no trial.
if ! codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q icloud; then
    echo "error: $APP has no iCloud entitlements — wrong configuration archived" >&2
    exit 1
fi

cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>export</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
    <key>manageAppVersionAndBuildNumber</key><false/>
    <key>uploadSymbols</key><true/>
</dict>
</plist>
EOF

echo "==> Exporting $VERSION ($BUILD)"
xcodebuild -exportArchive -allowProvisioningUpdates "${AUTH[@]}" \
    -archivePath "$ARCHIVE" -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export"

PKG=$(ls "$OUT"/export/*.pkg | head -1)

if $UPLOAD; then
    echo "==> Uploading $PKG to App Store Connect"
    xcrun altool --upload-app -f "$PKG" -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
    echo "==> Uploaded. Finish in App Store Connect: pick build $BUILD for version $VERSION,"
    echo "    add the What's New text, and submit for review."
else
    echo "==> $PKG (pass --upload to send it to App Store Connect)"
fi
