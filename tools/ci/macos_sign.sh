#!/usr/bin/env bash
# Signs the macOS zip from tools/export_build.sh ("macos") with a Developer ID certificate,
# notarizes it with Apple and staples the ticket, so macOS opens it without the "unknown developer"
# warning (release.yml job "macos-sign", docs/STORES.md). macOS with Xcode command line tools only.
# The zip is replaced in place; LIESMICH.txt stays in it.
#
#   tools/ci/macos_sign.sh builds/<env>/<version>/Soulwick-<v>-<env>-macos.zip
#
# Secrets (environment):
#   APPLE_TEAM_ID                       10-character team ID
#   MACOS_DEVELOPER_ID_CERT_BASE64      "Developer ID Application" certificate with key (.p12), base64
#   MACOS_DEVELOPER_ID_CERT_PASSWORD    password of that .p12
#   APP_STORE_CONNECT_API_KEY_ID, APP_STORE_CONNECT_API_ISSUER_ID, APP_STORE_CONNECT_API_KEY_BASE64
#                                       API key for notarytool (same key as for TestFlight)
# Hardened runtime without exceptions: Soulwick has no JIT and no foreign libraries. When GodotSteam
# (MP6/MP10) ships libsteam_api.dylib, that dylib is signed here too (all of Contents/Frameworks).
set -euo pipefail

ZIP="${1:?usage: macos_sign.sh <macos zip>}"
# shellcheck source=tools/ci/apple_keychain.sh
. "$(dirname "${BASH_SOURCE[0]}")/apple_keychain.sh"
trap apple_cleanup EXIT

[ -f "$ZIP" ] || apple_fail "$ZIP does not exist."
for name in APPLE_TEAM_ID MACOS_DEVELOPER_ID_CERT_BASE64 MACOS_DEVELOPER_ID_CERT_PASSWORD; do
	[ -n "${!name:-}" ] || apple_fail "macOS signing: secret $name is missing."
done

apple_init
apple_api_key
apple_import_p12 "$MACOS_DEVELOPER_ID_CERT_BASE64" "$MACOS_DEVELOPER_ID_CERT_PASSWORD" developer-id
identity="$(apple_identity "Developer ID Application")"
[ -n "$identity" ] || apple_fail "MACOS_DEVELOPER_ID_CERT_BASE64 holds no valid 'Developer ID Application' identity."

work="$APPLE_WORK/app"
mkdir -p "$work"
ditto -x -k "$ZIP" "$work"
app="$(find "$work" -maxdepth 1 -name '*.app' | head -n 1)"
[ -n "$app" ] || apple_fail "No .app in $ZIP."

sign() {
	codesign --force --timestamp --options runtime --keychain "$APPLE_KEYCHAIN" --sign "$identity" "$@"
}
# Inside out: nested libraries and frameworks first, then the app itself (no --deep).
if [ -d "$app/Contents/Frameworks" ]; then
	while IFS= read -r -d '' nested; do
		sign "$nested"
	done < <(find "$app/Contents/Frameworks" -depth \( -name '*.dylib' -o -name '*.framework' \) -print0)
fi
sign "$app"
codesign --verify --deep --strict --verbose=2 "$app"

echo "Notarizing (usually a few minutes) ..."
submit="$APPLE_WORK/notarize.zip"
ditto -c -k --keepParent "$app" "$submit"
result="$APPLE_WORK/notary.json"
xcrun notarytool submit "$submit" --key "$APPLE_API_KEY_PATH" --key-id "$APP_STORE_CONNECT_API_KEY_ID" \
	--issuer "$APP_STORE_CONNECT_API_ISSUER_ID" --wait --timeout 1h --output-format json > "$result" || true
status="$(/usr/bin/plutil -extract status raw -o - "$result" 2>/dev/null || true)"
submission="$(/usr/bin/plutil -extract id raw -o - "$result" 2>/dev/null || true)"
if [ "$status" != "Accepted" ]; then
	cat "$result" >&2 || true
	if [ -n "$submission" ]; then
		xcrun notarytool log "$submission" --key "$APPLE_API_KEY_PATH" --key-id "$APP_STORE_CONNECT_API_KEY_ID" \
			--issuer "$APP_STORE_CONNECT_API_ISSUER_ID" >&2 || true
	fi
	apple_fail "Notarization was not accepted (status '${status:-none}')."
fi
xcrun stapler staple "$app"
spctl --assess --type execute --verbose=2 "$app"

# Same layout as before: Soulwick.app plus LIESMICH.txt at the top of the zip.
signed="$APPLE_WORK/signed.zip"
(cd "$work" && ditto -c -k --sequesterRsrc --keepParent "$(basename "$app")" "$signed")
if [ -f "$work/LIESMICH.txt" ]; then
	(cd "$work" && zip -q "$signed" LIESMICH.txt)
fi
mv "$signed" "$ZIP"
echo "Signed, notarized and stapled: $ZIP"
