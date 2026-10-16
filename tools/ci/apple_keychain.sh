#!/usr/bin/env bash
# Shared helpers for tools/ci/ios_build.sh and tools/ci/macos_sign.sh (macOS only, sourced):
# a temporary keychain for one CI run, the App Store Connect API key as a file.
# Nothing here prints a secret; files land in $APPLE_WORK (private temp folder), the keychain is
# deleted by apple_cleanup (call it from an EXIT trap).
#
#   . tools/ci/apple_keychain.sh
#   apple_init                       # creates $APPLE_WORK and the keychain $APPLE_KEYCHAIN
#   apple_import_p12 <base64> <password> <label>
#   apple_api_key                    # writes AuthKey_<id>.p8, sets APPLE_API_KEY_PATH
#   apple_cleanup

apple_fail() {
	echo "::error::$1" >&2
	exit 1
}

apple_decode() {
	# base64 (with or without line breaks) -> file
	printf '%s' "$1" | tr -d '\r\n ' | base64 --decode > "$2" 2>/dev/null || apple_fail "$3 is not valid base64."
	[ -s "$2" ] || apple_fail "$3 is empty after decoding."
}

apple_init() {
	[ "$(uname -s)" = "Darwin" ] || apple_fail "Apple signing needs a Mac (runs-on: macos-latest)."
	APPLE_WORK="$(mktemp -d)"
	chmod 700 "$APPLE_WORK"
	APPLE_KEYCHAIN="$APPLE_WORK/soulwick-ci.keychain-db"
	APPLE_KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"
	security create-keychain -p "$APPLE_KEYCHAIN_PASSWORD" "$APPLE_KEYCHAIN"
	# No auto lock during a long build (6 h), unlocked for codesign.
	security set-keychain-settings -lut 21600 "$APPLE_KEYCHAIN"
	security unlock-keychain -p "$APPLE_KEYCHAIN_PASSWORD" "$APPLE_KEYCHAIN"
	# Search list: our keychain first, the existing ones after it.
	local existing
	existing="$(security list-keychains -d user | tr -d '"' | xargs)"
	# shellcheck disable=SC2086
	security list-keychains -d user -s "$APPLE_KEYCHAIN" $existing
	export APPLE_WORK APPLE_KEYCHAIN
}

apple_import_p12() {
	local file="$APPLE_WORK/$3.p12"
	apple_decode "$1" "$file" "$3"
	security import "$file" -k "$APPLE_KEYCHAIN" -P "$2" -f pkcs12 -A -T /usr/bin/codesign -T /usr/bin/security >/dev/null ||
		apple_fail "$3: the certificate does not open with the given password."
	rm -f "$file"
	# codesign may use the key without a dialog.
	security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$APPLE_KEYCHAIN_PASSWORD" "$APPLE_KEYCHAIN" >/dev/null
}

# SHA-1 of the first valid identity whose name starts with $1 ("Apple Distribution", "Developer ID Application").
apple_identity() {
	security find-identity -v -p codesigning "$APPLE_KEYCHAIN" | awk -v want="\"$1" 'index($0, want) { print $2; exit }'
}

apple_api_key() {
	local name
	for name in APP_STORE_CONNECT_API_KEY_ID APP_STORE_CONNECT_API_ISSUER_ID APP_STORE_CONNECT_API_KEY_BASE64; do
		[ -n "${!name:-}" ] || apple_fail "App Store Connect API key: secret $name is missing."
	done
	# altool looks for the key in ~/.appstoreconnect/private_keys or $API_PRIVATE_KEYS_DIR.
	mkdir -p "$APPLE_WORK/private_keys"
	APPLE_API_KEY_PATH="$APPLE_WORK/private_keys/AuthKey_$APP_STORE_CONNECT_API_KEY_ID.p8"
	apple_decode "$APP_STORE_CONNECT_API_KEY_BASE64" "$APPLE_API_KEY_PATH" APP_STORE_CONNECT_API_KEY_BASE64
	grep -q "BEGIN PRIVATE KEY" "$APPLE_API_KEY_PATH" || apple_fail "APP_STORE_CONNECT_API_KEY_BASE64 is not a .p8 key (base64 of the whole file)."
	export API_PRIVATE_KEYS_DIR="$APPLE_WORK/private_keys" APPLE_API_KEY_PATH
}

apple_cleanup() {
	if [ -n "${APPLE_KEYCHAIN:-}" ] && [ -f "$APPLE_KEYCHAIN" ]; then
		security delete-keychain "$APPLE_KEYCHAIN" >/dev/null 2>&1 || true
	fi
	# Installed provisioning profiles, one path per line.
	if [ -n "${APPLE_PROFILE_INSTALLED:-}" ]; then
		local path
		while IFS= read -r path; do
			[ -n "$path" ] && rm -f "$path"
		done <<< "$APPLE_PROFILE_INSTALLED"
	fi
	if [ -n "${APPLE_WORK:-}" ]; then
		rm -rf "$APPLE_WORK"
	fi
}
