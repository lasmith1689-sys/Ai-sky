#!/bin/bash
# Builds Ai Sky for the App Store and, when App Store Connect credentials are configured,
# uploads it to TestFlight. See TESTFLIGHT.md.
#
# No Mac, certificates or provisioning profiles are needed. Like Xcode Cloud, the archive is
# ad-hoc signed (which embeds the App Group and WeatherKit entitlements without any certificate),
# and Xcode signs it for distribution during export with a cloud-managed certificate, using the
# App Store Connect API key.
#
# Environment:
#   BUILD_NUMBER                  required, e.g. "12.1" (must grow with every upload)
#   APPLE_TEAM_ID, ASC_KEY_ID,    optional; without all four the script stops after a dry-run
#   ASC_ISSUER_ID, ASC_KEY_P8     archive. ASC_KEY_P8 is the text of the AuthKey_XXXX.p8 file.
#   AISKY_BUNDLE_ID_PREFIX        optional override of Config/Shared.xcconfig
#   AISKY_ENABLE_WEATHERKIT       optional, YES to include Apple Weather
set -euo pipefail

OUT="${RUNNER_TEMP:-/tmp}/testflight"
ARCHIVE="$OUT/AiSky.xcarchive"
rm -rf "$OUT"
mkdir -p "$OUT"

prefix="${AISKY_BUNDLE_ID_PREFIX:-}"
if [ -z "$prefix" ]; then
  prefix=$(sed -n 's/^AISKY_BUNDLE_ID_PREFIX *= *//p' Config/Shared.xcconfig | tr -d '[:space:]')
fi
settings=(
  "CURRENT_PROJECT_VERSION=$BUILD_NUMBER"
  "AISKY_BUNDLE_ID_PREFIX=$prefix"
)
if [ -n "${AISKY_ENABLE_WEATHERKIT:-}" ]; then
  settings+=("AISKY_ENABLE_WEATHERKIT=$AISKY_ENABLE_WEATHERKIT")
fi

echo "▶ Archiving Ai Sky $prefix.AiSky, build $BUILD_NUMBER"
if ! xcodebuild archive \
    -project AiSky.xcodeproj \
    -scheme AiSky \
    -configuration Release \
    -destination generic/platform=iOS \
    -archivePath "$ARCHIVE" \
    -skipPackagePluginValidation \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    AD_HOC_CODE_SIGNING_ALLOWED=YES \
    PROVISIONING_PROFILE_SPECIFIER= \
    "${settings[@]}" > "$OUT/archive.log" 2>&1; then
  grep -E "error:|warning:" "$OUT/archive.log" | sort -u | head -50 || true
  tail -n 40 "$OUT/archive.log"
  echo "::error::The App Store build failed. See the log above."
  exit 1
fi
grep -E "warning:" "$OUT/archive.log" | sort -u | head -20 || true

# The export keeps whatever entitlements the archive carries, so check them now.
app="$ARCHIVE/Products/Applications/AiSky.app"
widget="$app/PlugIns/AiSkyWidgetsExtension.appex"
group="group.$prefix.AiSky"
for bundle in "$app" "$widget"; do
  entitlements=$(codesign -d --entitlements - --xml "$bundle" 2>/dev/null || true)
  echo "Entitlements of ${bundle##*/}: $(echo "$entitlements" | plutil -convert json -o - - 2>/dev/null || echo "$entitlements")"
  if [[ "$entitlements" != *"$group"* ]]; then
    echo "::error::${bundle##*/} is missing the App Group $group, so the widgets couldn't see your places."
    exit 1
  fi
done
plutil -p "$app/Info.plist" | grep -E '"CFBundleIdentifier"|"CFBundleShortVersionString"|"CFBundleVersion"|ITSAppUsesNonExemptEncryption' || true

if [ -z "${APPLE_TEAM_ID:-}" ] || [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ] || [ -z "${ASC_KEY_P8:-}" ]; then
  echo "::notice::App Store build OK. Nothing was uploaded: add the App Store Connect secrets (see TESTFLIGHT.md) to send builds to TestFlight."
  exit 0
fi

key="$OUT/AuthKey_$ASC_KEY_ID.p8"
# Accept the .p8 text however it was pasted: Windows line endings, or without the BEGIN/END lines.
p8=$(printf '%s' "$ASC_KEY_P8" | tr -d '\r')
if [[ "$p8" != *"BEGIN PRIVATE KEY"* ]]; then
  p8=$(printf -- '-----BEGIN PRIVATE KEY-----\n%s\n-----END PRIVATE KEY-----' "$(printf '%s' "$p8" | tr -d ' \n' | fold -w 64)")
fi
(umask 077 && printf '%s\n' "$p8" > "$key")
unset p8
trap 'rm -f "$key"' EXIT

cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>$APPLE_TEAM_ID</string>
	<key>testFlightInternalTestingOnly</key>
	<true/>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
EOF

echo "▶ Signing and uploading to App Store Connect"
if ! xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -exportPath "$OUT/export" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$key" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" > "$OUT/export.log" 2>&1; then
  tail -n 60 "$OUT/export.log"
  log=$(cat "$OUT/export.log")
  hint="See TESTFLIGHT.md."
  case "$log" in
    *"No suitable application records"*|*"Cannot determine the Apple ID from Bundle ID"*)
      hint="Create the app in App Store Connect with bundle ID $prefix.AiSky (TESTFLIGHT.md, step 3)." ;;
    *"com.apple.security.application-groups"*|*"App Group"*)
      hint="Register the App Group $group and turn it on for both App IDs (TESTFLIGHT.md, step 2)." ;;
    *"com.apple.developer.weatherkit"*)
      hint="Turn on WeatherKit for $prefix.AiSky under both Capabilities and App Services, or set AISKY_ENABLE_WEATHERKIT back to NO." ;;
    *"NOT_AUTHORIZED"*|*"not authorized"*|*"credentials are missing or invalid"*|*"loud signing permission"*|*"does not have permission"*|*"invalid key"*|*"Invalid key"*)
      hint="Check the API key: it needs the Admin role, and ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 must all come from that key (TESTFLIGHT.md, step 4)." ;;
    *"bundle version must be higher"*)
      hint="That build number was already used. Run the workflow again to get a new one." ;;
  esac
  echo "::error::Upload to TestFlight failed. $hint"
  exit 1
fi
grep -iE "upload|success|export" "$OUT/export.log" | tail -n 5 || true
echo "::notice::Uploaded Ai Sky build $BUILD_NUMBER. It shows up in TestFlight once Apple finishes processing it, usually within 5–30 minutes."
