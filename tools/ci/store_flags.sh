#!/usr/bin/env bash
# Decides which optional release jobs run (release.yml, docs/STORES.md): signing and store uploads
# need secrets; without them the jobs are skipped, the run stays green. Writes key=true|false lines
# to $GITHUB_OUTPUT (or stdout) and a table to the run summary. Only checks whether a secret is set;
# never prints a value.
#
# Input (environment, from secrets and variables):
#   EVENT, INPUT_STORE_UPLOAD       push | workflow_dispatch; form field "store_upload"
#   ANDROID_KEYSTORE_BASE64         -> aab (Google Play bundle, signed with the upload key)
#   PLAY_SERVICE_ACCOUNT_JSON       -> play_upload (internal test track)
#   APPLE_TEAM_ID, IOS_DISTRIBUTION_CERT_BASE64, IOS_PROVISIONING_PROFILE_BASE64 -> ios_sign (.ipa)
#   APP_STORE_CONNECT_API_KEY_BASE64 -> testflight (with ios_sign), needed by macos_sign
#   MACOS_DEVELOPER_ID_CERT_BASE64  -> macos_sign (Developer ID + notarization)
#   AZURE_SIGNING_ENDPOINT or WINDOWS_SIGN_PFX_BASE64 -> windows_sign
#   STEAM_USERNAME, STEAM_CONFIG_VDF (secrets), STEAM_APP_ID (variable) -> steam
# German quotes in the summary are intended.
# shellcheck disable=SC1111
set -euo pipefail

set_() { [ -n "${!1:-}" ]; }
flag() { if "$@"; then echo true; else echo false; fi; }

store_upload=true
if [ "${EVENT:-push}" = "workflow_dispatch" ] && [ "${INPUT_STORE_UPLOAD:-true}" != "true" ]; then
	store_upload=false
fi

aab="$(flag set_ ANDROID_KEYSTORE_BASE64)"
play_upload=false
if [ "$aab" = true ] && [ "$store_upload" = true ] && set_ PLAY_SERVICE_ACCOUNT_JSON; then play_upload=true; fi

ios_sign=false
if set_ APPLE_TEAM_ID && set_ IOS_DISTRIBUTION_CERT_BASE64 && set_ IOS_PROVISIONING_PROFILE_BASE64; then ios_sign=true; fi
testflight=false
if [ "$ios_sign" = true ] && [ "$store_upload" = true ] && set_ APP_STORE_CONNECT_API_KEY_BASE64; then testflight=true; fi

macos_sign=false
if set_ MACOS_DEVELOPER_ID_CERT_BASE64; then
	if set_ APPLE_TEAM_ID && set_ APP_STORE_CONNECT_API_KEY_BASE64; then
		macos_sign=true
	else
		echo "::warning::MACOS_DEVELOPER_ID_CERT_BASE64 is set, but notarization needs APPLE_TEAM_ID and the App Store Connect API key too; the macOS build stays unsigned."
	fi
fi

windows_sign=false
if set_ AZURE_SIGNING_ENDPOINT || set_ WINDOWS_SIGN_PFX_BASE64; then windows_sign=true; fi

steam=false
if set_ STEAM_USERNAME && set_ STEAM_CONFIG_VDF; then
	if ! set_ STEAM_APP_ID; then
		echo "::warning::Steam secrets are set, but the repository variable STEAM_APP_ID is missing; no Steam upload."
	elif [ "$store_upload" = true ]; then
		steam=true
	fi
fi

out="${GITHUB_OUTPUT:-/dev/stdout}"
{
	echo "store_upload=$store_upload"
	echo "aab=$aab"
	echo "play_upload=$play_upload"
	echo "ios_sign=$ios_sign"
	echo "testflight=$testflight"
	echo "macos_sign=$macos_sign"
	echo "windows_sign=$windows_sign"
	echo "steam=$steam"
} >> "$out"

yes_no() { if [ "$1" = true ]; then echo "ja"; else echo "nein"; fi; }
summary="${GITHUB_STEP_SUMMARY:-/dev/stderr}"
{
	echo "### Signaturen und Stores in diesem Lauf"
	echo
	echo "| Schritt | läuft | fehlt dafür (docs/STORES.md) |"
	echo "| --- | --- | --- |"
	echo "| Windows signieren | $(yes_no "$windows_sign") | \`AZURE_SIGNING_*\` oder \`WINDOWS_SIGN_PFX_*\` |"
	echo "| macOS signieren + notarisieren | $(yes_no "$macos_sign") | \`MACOS_DEVELOPER_ID_CERT_*\`, \`APPLE_TEAM_ID\`, \`APP_STORE_CONNECT_API_*\` |"
	echo "| Android-AAB (Google Play) | $(yes_no "$aab") | \`ANDROID_KEYSTORE_*\` |"
	echo "| Upload Play „Interner Test“ | $(yes_no "$play_upload") | \`PLAY_SERVICE_ACCOUNT_JSON\` |"
	echo "| iOS-IPA signiert | $(yes_no "$ios_sign") | \`APPLE_TEAM_ID\`, \`IOS_DISTRIBUTION_CERT_*\`, \`IOS_PROVISIONING_PROFILE_BASE64\` |"
	echo "| Upload TestFlight | $(yes_no "$testflight") | \`APP_STORE_CONNECT_API_*\` |"
	echo "| Upload Steam (Beta-Branch) | $(yes_no "$steam") | \`STEAM_USERNAME\`, \`STEAM_CONFIG_VDF\`, Variable \`STEAM_APP_ID\` |"
	echo
	echo "Store-Uploads in diesem Lauf: $(yes_no "$store_upload"). Das iOS-Xcode-Projekt entsteht immer."
} >> "$summary"
