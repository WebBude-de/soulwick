#!/usr/bin/env bash
# Picks the keystore that signs the Android APK of a release run (release.yml, docs/RELEASE.md)
# and hands it to tools/export_build.sh through GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD
# (written to $GITHUB_ENV; never echoed). The keystore file lands in $RUNNER_TEMP, never in the repo.
#
#   production:  release key from ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD,
#                ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD (GitHub secrets).
#   development: the shared debug key from ANDROID_DEBUG_KEYSTORE_BASE64 (the debug.keystore of the
#                build PC, alias androiddebugkey, password android), so CI APKs install as updates
#                over locally built ones.
#   Fallbacks: production without release key uses the shared debug key, otherwise (both
#   environments) a fresh debug key is generated. Such an APK is "test only" (test_signed=true marks
#   the release); a fresh key also means a phone with an older Soulwick APK has to uninstall first.
#   REQUIRE_RELEASE_KEY=1 (Google Play AAB, both environments): always the release key (= Play
#   upload key), no fallback; fails without it.
#
# Output ($GITHUB_OUTPUT or stdout): signing=release|debug-shared|debug-new, test_signed=true|false.
# Needs keytool (JDK 17) on PATH or in JAVA_HOME.
set -euo pipefail

ENVIRONMENT="${ENVIRONMENT:-development}"
WORK="${RUNNER_TEMP:-$(mktemp -d)}/android-signing"
mkdir -p "$WORK"
chmod 700 "$WORK"
KEYTOOL="keytool"
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/keytool" ]; then
	KEYTOOL="$JAVA_HOME/bin/keytool"
fi

fail() {
	echo "::error::$1" >&2
	exit 1
}

decode() {
	# Accepts base64 with or without line breaks (base64 -w0 or certutil output).
	printf '%s' "$1" | tr -d '\r\n ' | base64 -d > "$2" 2>/dev/null || fail "$3 is not valid base64."
	[ -s "$2" ] || fail "$3 is empty after decoding."
}

check_alias() {
	# keystore, store password, alias, label
	"$KEYTOOL" -list -keystore "$1" -storepass "$2" -alias "$3" >/dev/null 2>&1 ||
		fail "$4: keystore does not open with the given password or has no alias '$3'."
}

keystore=""
user=""
password=""
signing=""
test_signed=false

REQUIRE_RELEASE_KEY="${REQUIRE_RELEASE_KEY:-0}"
if [ "$REQUIRE_RELEASE_KEY" = "1" ] && [ -z "${ANDROID_KEYSTORE_BASE64:-}" ]; then
	fail "The Google Play bundle needs the release (upload) key: secret ANDROID_KEYSTORE_BASE64 is missing."
fi

if { [ "$ENVIRONMENT" = "production" ] || [ "$REQUIRE_RELEASE_KEY" = "1" ]; } && [ -n "${ANDROID_KEYSTORE_BASE64:-}" ]; then
	[ -n "${ANDROID_KEYSTORE_PASSWORD:-}" ] || fail "ANDROID_KEYSTORE_PASSWORD is missing."
	[ -n "${ANDROID_KEY_ALIAS:-}" ] || fail "ANDROID_KEY_ALIAS is missing."
	keystore="$WORK/release.keystore"
	decode "$ANDROID_KEYSTORE_BASE64" "$keystore" ANDROID_KEYSTORE_BASE64
	user="$ANDROID_KEY_ALIAS"
	password="$ANDROID_KEYSTORE_PASSWORD"
	check_alias "$keystore" "$password" "$user" "Release key"
	key_password="${ANDROID_KEY_PASSWORD:-$password}"
	if [ "$key_password" != "$password" ]; then
		# Godot passes one password to apksigner (store = key). A JKS keystore with its own key
		# password is copied into a PKCS12 keystore with one password (same key, same signature).
		unified="$WORK/release-unified.p12"
		"$KEYTOOL" -importkeystore -noprompt \
			-srckeystore "$keystore" -srcstorepass "$password" -srcalias "$user" -srckeypass "$key_password" \
			-destkeystore "$unified" -deststoretype PKCS12 -deststorepass "$password" -destkeypass "$password" \
			>/dev/null 2>&1 || fail "Release key: ANDROID_KEY_PASSWORD does not open the key '$user'."
		rm -f "$keystore"
		keystore="$unified"
	fi
	signing=release
	# The certificate fingerprint is public (Play Console -> App integrity shows the same value).
	"$KEYTOOL" -list -v -keystore "$keystore" -storepass "$password" -alias "$user" 2>/dev/null |
		grep -m 1 -E "SHA256:" | sed 's/^[[:space:]]*/Release key /' >&2 || true
elif [ -n "${ANDROID_DEBUG_KEYSTORE_BASE64:-}" ]; then
	if [ "$ENVIRONMENT" = "production" ]; then
		echo "::warning::No release key (secret ANDROID_KEYSTORE_BASE64): the production APK is signed with the shared debug key and the release is marked as test only."
		test_signed=true
	fi
	keystore="$WORK/debug.keystore"
	decode "$ANDROID_DEBUG_KEYSTORE_BASE64" "$keystore" ANDROID_DEBUG_KEYSTORE_BASE64
	user=androiddebugkey
	password=android
	check_alias "$keystore" "$password" "$user" "Debug key (ANDROID_DEBUG_KEYSTORE_BASE64)"
	signing=debug-shared
else
	if [ "$ENVIRONMENT" = "production" ]; then
		echo "::warning::No release key (secret ANDROID_KEYSTORE_BASE64): the production APK is signed with a new debug key and the release is marked as test only."
	else
		echo "::warning::No shared debug key (secret ANDROID_DEBUG_KEYSTORE_BASE64): the APK is signed with a new debug key; phones with an older Soulwick APK must uninstall it first."
	fi
	keystore="$WORK/debug.keystore"
	user=androiddebugkey
	password=android
	"$KEYTOOL" -genkeypair -keystore "$keystore" -storepass "$password" -alias "$user" -keypass "$password" \
		-keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1 ||
		fail "keytool could not create a debug keystore."
	signing=debug-new
	test_signed=true
fi

if [ -n "${GITHUB_ENV:-}" ]; then
	{
		echo "GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$keystore"
		echo "GODOT_ANDROID_KEYSTORE_RELEASE_USER=$user"
		echo "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=$password"
	} >> "$GITHUB_ENV"
else
	echo "GITHUB_ENV not set: export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$keystore (user $user) yourself." >&2
fi

echo "Android signing: $signing (test only: $test_signed)" >&2
out="${GITHUB_OUTPUT:-/dev/stdout}"
{
	echo "signing=$signing"
	echo "test_signed=$test_signed"
} >> "$out"
