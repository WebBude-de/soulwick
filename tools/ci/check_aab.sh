#!/usr/bin/env bash
# Checks an Android App Bundle before it goes to Google Play (release.yml job "android-aab"):
# package name, versionCode, versionName, min/target SDK (bundletool) and the upload signature
# (jarsigner). Fails when the target SDK is below Google Play's requirement.
#
#   tools/ci/check_aab.sh builds/<env>/<version>/Soulwick-<v>-<env>-android.aab [expected versionCode]
#
# Environment: MIN_TARGET_SDK (default 36: Google Play's target API level for new apps and updates
# from 31.08.2026, docs/STORES.md), PACKAGE (default com.webbude.soulwick). Needs Java (JDK 17).
set -euo pipefail

AAB="${1:?usage: check_aab.sh <aab> [versionCode]}"
EXPECTED_CODE="${2:-}"
MIN_TARGET_SDK="${MIN_TARGET_SDK:-36}"
PACKAGE="${PACKAGE:-com.webbude.soulwick}"
BUNDLETOOL_VERSION="1.18.3"
BUNDLETOOL_SHA256="a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29"
TOOLS="${RUNNER_TOOL_CACHE:-${TMPDIR:-/tmp}}/bundletool-$BUNDLETOOL_VERSION"

fail() {
	echo "::error::$1" >&2
	exit 1
}

sha256() {
	if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d ' ' -f1; else shasum -a 256 "$1" | cut -d ' ' -f1; fi
}

[ -f "$AAB" ] || fail "$AAB does not exist."
jar="$TOOLS/bundletool.jar"
if [ ! -f "$jar" ] || [ "$(sha256 "$jar")" != "$BUNDLETOOL_SHA256" ]; then
	mkdir -p "$TOOLS"
	curl -fsSL --retry 3 -o "$jar" "https://github.com/google/bundletool/releases/download/$BUNDLETOOL_VERSION/bundletool-all-$BUNDLETOOL_VERSION.jar"
	[ "$(sha256 "$jar")" = "$BUNDLETOOL_SHA256" ] || { rm -f "$jar"; fail "bundletool download has the wrong checksum."; }
fi

attribute() {
	java -jar "$jar" dump manifest --bundle "$AAB" --xpath "$1" 2>/dev/null | tr -d '\r\n'
}
package="$(attribute /manifest/@package)"
version_code="$(attribute /manifest/@android:versionCode)"
version_name="$(attribute /manifest/@android:versionName)"
min_sdk="$(attribute /manifest/uses-sdk/@android:minSdkVersion)"
target_sdk="$(attribute /manifest/uses-sdk/@android:targetSdkVersion)"
echo "package=$package versionCode=$version_code versionName=$version_name minSdk=$min_sdk targetSdk=$target_sdk"

[ "$package" = "$PACKAGE" ] || fail "AAB package is '$package', expected $PACKAGE."
if [ -n "$EXPECTED_CODE" ] && [ "$version_code" != "$EXPECTED_CODE" ]; then
	fail "AAB versionCode is $version_code, expected $EXPECTED_CODE."
fi
case "$target_sdk" in ''|*[!0-9]*) fail "AAB has no readable targetSdkVersion." ;; esac
[ "$target_sdk" -ge "$MIN_TARGET_SDK" ] || fail "targetSdk $target_sdk is below Google Play's minimum $MIN_TARGET_SDK (gradle_build/target_sdk)."

# Upload signature: the AAB is signed like a jar (v1). Print the certificate fingerprint only.
jarsigner_bin="jarsigner"
[ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/jarsigner" ] && jarsigner_bin="$JAVA_HOME/bin/jarsigner"
verify="$("$jarsigner_bin" -verify -verbose:summary -certs "$AAB" 2>&1)" || { echo "$verify" | tail -n 20; fail "jarsigner: the AAB signature is invalid."; }
# Here-strings: the output is long, "echo | grep -q" would fail with SIGPIPE under pipefail.
grep -q "^jar verified" <<< "$verify" || { tail -n 20 <<< "$verify"; fail "jarsigner: the AAB is not signed."; }
grep -m 1 -E "X.509, " <<< "$verify" | sed 's/^[[:space:]]*/Signer: /' || true
echo "AAB check passed: $AAB"
