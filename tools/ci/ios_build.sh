#!/usr/bin/env bash
# Archives, signs and packs the iOS Xcode project from tools/export_build.sh ("ios") into an .ipa
# for the App Store, optionally uploads it to TestFlight (release.yml job "ios", docs/STORES.md).
# macOS with Xcode only.
#
#   tools/ci/ios_build.sh builds/<env>/<version>/ios builds/<env>/<version>/Soulwick-<v>-<env>-ios.ipa
#
# Secrets (environment):
#   APPLE_TEAM_ID                    10-character team ID (Apple Developer -> Membership)
#   IOS_DISTRIBUTION_CERT_BASE64     "Apple Distribution" certificate with private key (.p12), base64
#   IOS_DISTRIBUTION_CERT_PASSWORD   password of that .p12
#   IOS_PROVISIONING_PROFILE_BASE64  App Store provisioning profile for com.webbude.soulwick, base64
# Upload (IOS_UPLOAD=1): APP_STORE_CONNECT_API_KEY_ID, APP_STORE_CONNECT_API_ISSUER_ID,
#   APP_STORE_CONNECT_API_KEY_BASE64 (the .p8 file, base64). The build then appears in App Store
#   Connect -> TestFlight after Apple's processing (a few minutes up to an hour).
set -euo pipefail

IOS_DIR="${1:?usage: ios_build.sh <ios export folder> <ipa>}"
IPA="${2:?usage: ios_build.sh <ios export folder> <ipa>}"
BUNDLE_ID="${BUNDLE_ID:-com.webbude.soulwick}"
SCHEME="Soulwick"
# shellcheck source=tools/ci/apple_keychain.sh
. "$(dirname "${BASH_SOURCE[0]}")/apple_keychain.sh"
trap apple_cleanup EXIT

[ -d "$IOS_DIR/$SCHEME.xcodeproj" ] || apple_fail "$IOS_DIR/$SCHEME.xcodeproj is missing (run tools/export_build.sh ... ios first)."
for name in APPLE_TEAM_ID IOS_DISTRIBUTION_CERT_BASE64 IOS_DISTRIBUTION_CERT_PASSWORD IOS_PROVISIONING_PROFILE_BASE64; do
	[ -n "${!name:-}" ] || apple_fail "iOS signing: secret $name is missing."
done

apple_init
apple_import_p12 "$IOS_DISTRIBUTION_CERT_BASE64" "$IOS_DISTRIBUTION_CERT_PASSWORD" ios-distribution
# Xcode picks the certificate by its common name; the keychain holds only this one.
identity="Apple Distribution"
if [ -z "$(apple_identity "$identity")" ]; then
	identity="iPhone Distribution"
	[ -n "$(apple_identity "$identity")" ] ||
		apple_fail "IOS_DISTRIBUTION_CERT_BASE64 holds no valid 'Apple Distribution' identity (expired or without private key?)."
fi

# Provisioning profile: read UUID, team and app ID, install it where Xcode looks.
profile="$APPLE_WORK/profile.mobileprovision"
apple_decode "$IOS_PROVISIONING_PROFILE_BASE64" "$profile" IOS_PROVISIONING_PROFILE_BASE64
security cms -D -i "$profile" > "$APPLE_WORK/profile.plist" 2>/dev/null || apple_fail "IOS_PROVISIONING_PROFILE_BASE64 is not a provisioning profile."
plist() { /usr/libexec/PlistBuddy -c "Print $1" "$APPLE_WORK/profile.plist" 2>/dev/null || true; }
profile_uuid="$(plist :UUID)"
profile_name="$(plist :Name)"
profile_team="$(plist :TeamIdentifier:0)"
profile_app="$(plist :Entitlements:application-identifier)"
profile_expiry="$(plist :ExpirationDate)"
[ -n "$profile_uuid" ] || apple_fail "The provisioning profile has no UUID."
[ "$profile_team" = "$APPLE_TEAM_ID" ] || apple_fail "The provisioning profile belongs to team $profile_team, not APPLE_TEAM_ID."
[ "$profile_app" = "$APPLE_TEAM_ID.$BUNDLE_ID" ] || apple_fail "The provisioning profile is for '$profile_app', not '$APPLE_TEAM_ID.$BUNDLE_ID'."
if [ -n "$(plist :ProvisionedDevices)" ]; then
	apple_fail "The provisioning profile lists devices (development/ad hoc); TestFlight needs an App Store profile."
fi
echo "Provisioning profile: $profile_name ($profile_uuid), valid until $profile_expiry"
APPLE_PROFILE_INSTALLED=""
for dir in "$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
	mkdir -p "$dir"
	cp "$profile" "$dir/$profile_uuid.mobileprovision"
	APPLE_PROFILE_INSTALLED="$APPLE_PROFILE_INSTALLED$dir/$profile_uuid.mobileprovision"$'\n'
done

xcodebuild -version
archive="$APPLE_WORK/$SCHEME.xcarchive"
echo "Archiving $SCHEME (Release, manual signing) ..."
xcodebuild -quiet \
	-project "$IOS_DIR/$SCHEME.xcodeproj" -scheme "$SCHEME" -configuration Release \
	-sdk iphoneos -destination "generic/platform=iOS" -archivePath "$archive" archive \
	CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_IDENTITY="$identity" \
	PROVISIONING_PROFILE_SPECIFIER="$profile_uuid" OTHER_CODE_SIGN_FLAGS="--keychain $APPLE_KEYCHAIN" ||
	apple_fail "xcodebuild archive failed (see the log above)."

cat > "$APPLE_WORK/export_options.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>export</string>
	<key>teamID</key><string>$APPLE_TEAM_ID</string>
	<key>signingStyle</key><string>manual</string>
	<key>signingCertificate</key><string>$identity</string>
	<key>provisioningProfiles</key>
	<dict><key>$BUNDLE_ID</key><string>$profile_uuid</string></dict>
	<key>uploadSymbols</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
export_dir="$APPLE_WORK/export"
xcodebuild -quiet -exportArchive -archivePath "$archive" -exportOptionsPlist "$APPLE_WORK/export_options.plist" -exportPath "$export_dir" ||
	apple_fail "xcodebuild -exportArchive failed (see the log above)."
built="$(find "$export_dir" -maxdepth 1 -name '*.ipa' | head -n 1)"
[ -n "$built" ] || apple_fail "No .ipa after the export."
mkdir -p "$(dirname "$IPA")"
mv "$built" "$IPA"
echo "IPA: $IPA ($(du -h "$IPA" | cut -f1))"

if [ "${IOS_UPLOAD:-0}" = "1" ]; then
	apple_api_key
	echo "Uploading to App Store Connect (TestFlight) ..."
	xcrun altool --upload-app --type ios --file "$IPA" \
		--apiKey "$APP_STORE_CONNECT_API_KEY_ID" --apiIssuer "$APP_STORE_CONNECT_API_ISSUER_ID" ||
		apple_fail "Upload to App Store Connect failed. A build number that already exists needs a new version (docs/STORES.md)."
	echo "Uploaded. The build shows up in App Store Connect -> TestFlight after processing."
fi
