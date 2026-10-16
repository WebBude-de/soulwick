#!/usr/bin/env bash
# Authenticode signature for Soulwick.exe (tools/export_build.sh with WINDOWS_SIGN=1, release.yml;
# docs/STORES.md "Windows"). Runs on Linux, macOS and Git Bash: jsign (Java) signs and timestamps.
# Two ways, picked by the secrets that are set:
#
#   Azure Artifact Signing (formerly Trusted Signing, recommended: no hardware token):
#     AZURE_SIGNING_ENDPOINT   e.g. https://weu.codesigning.azure.net
#     AZURE_SIGNING_ACCOUNT    signing account name
#     AZURE_SIGNING_PROFILE    certificate profile name
#     AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET   app registration with the role
#                              "Artifact Signing Certificate Profile Signer" (formerly
#                              "Trusted Signing Certificate Profile Signer")
#   Certificate file (only for certificates that may live in a file, e.g. from before 06/2023):
#     WINDOWS_SIGN_PFX_BASE64, WINDOWS_SIGN_PFX_PASSWORD
#
#   tools/ci/sign_windows.sh builds/.../windows/Soulwick.exe
#
# Passwords and tokens reach jsign as env:NAME, never on the command line or in the log. The
# certificate file lands in a private temp folder and is deleted afterwards.
set -euo pipefail

FILE="${1:?usage: sign_windows.sh <exe>}"
JSIGN_VERSION="7.6"
JSIGN_SHA256="6cf58aa080e7ff82656f320cff8d4a3bff30408df8766806dcba3740dd839fa5"
TOOLS="${RUNNER_TOOL_CACHE:-${TMPDIR:-/tmp}}/jsign-$JSIGN_VERSION"
WORK="$(mktemp -d)"
chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT

fail() {
	echo "::error::$1" >&2
	exit 1
}

sha256() {
	if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d ' ' -f1; else shasum -a 256 "$1" | cut -d ' ' -f1; fi
}

[ -f "$FILE" ] || fail "sign_windows.sh: $FILE does not exist."
command -v java >/dev/null 2>&1 || fail "sign_windows.sh needs Java (JDK 11 or newer) on PATH."

jar="$TOOLS/jsign.jar"
if [ ! -f "$jar" ] || [ "$(sha256 "$jar")" != "$JSIGN_SHA256" ]; then
	mkdir -p "$TOOLS"
	curl -fsSL --retry 3 -o "$jar" "https://repo1.maven.org/maven2/net/jsign/jsign/$JSIGN_VERSION/jsign-$JSIGN_VERSION.jar"
	[ "$(sha256 "$jar")" = "$JSIGN_SHA256" ] || { rm -f "$jar"; fail "jsign download has the wrong checksum."; }
fi

args=(--name "Soulwick" --url "https://playsoulwick.com" --alg SHA-256 --tsmode RFC3161 --tsretries 3 --tsretrywait 10 --replace)
if [ -n "${AZURE_SIGNING_ENDPOINT:-}" ]; then
	for name in AZURE_SIGNING_ACCOUNT AZURE_SIGNING_PROFILE AZURE_TENANT_ID AZURE_CLIENT_ID AZURE_CLIENT_SECRET; do
		[ -n "${!name:-}" ] || fail "Windows signing (Azure): secret $name is missing."
	done
	# OAuth client credentials -> access token for the signing service (valid about an hour).
	response="$(curl -fsS --retry 3 -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" \
		--data-urlencode "grant_type=client_credentials" \
		--data-urlencode "client_id=$AZURE_CLIENT_ID" \
		--data-urlencode "client_secret=$AZURE_CLIENT_SECRET" \
		--data-urlencode "scope=https://codesigning.azure.net/.default")" || fail "Windows signing (Azure): no access token (check tenant, client ID and secret)."
	AZURE_SIGNING_TOKEN="$(printf '%s' "$response" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"
	[ -n "$AZURE_SIGNING_TOKEN" ] || fail "Windows signing (Azure): the token answer has no access_token."
	[ -n "${GITHUB_ACTIONS:-}" ] && echo "::add-mask::$AZURE_SIGNING_TOKEN"
	export AZURE_SIGNING_TOKEN
	endpoint="${AZURE_SIGNING_ENDPOINT#https://}"
	endpoint="${endpoint%/}"
	args+=(--storetype TRUSTEDSIGNING --keystore "$endpoint" --storepass env:AZURE_SIGNING_TOKEN
		--alias "$AZURE_SIGNING_ACCOUNT/$AZURE_SIGNING_PROFILE" --tsaurl "http://timestamp.acs.microsoft.com")
	mode="Azure Artifact Signing ($AZURE_SIGNING_ACCOUNT/$AZURE_SIGNING_PROFILE)"
elif [ -n "${WINDOWS_SIGN_PFX_BASE64:-}" ]; then
	[ -n "${WINDOWS_SIGN_PFX_PASSWORD:-}" ] || fail "Windows signing: secret WINDOWS_SIGN_PFX_PASSWORD is missing."
	printf '%s' "$WINDOWS_SIGN_PFX_BASE64" | tr -d '\r\n ' | base64 -d > "$WORK/cert.pfx" 2>/dev/null || fail "WINDOWS_SIGN_PFX_BASE64 is not valid base64."
	[ -s "$WORK/cert.pfx" ] || fail "WINDOWS_SIGN_PFX_BASE64 is empty after decoding."
	args+=(--storetype PKCS12 --keystore "$WORK/cert.pfx" --storepass env:WINDOWS_SIGN_PFX_PASSWORD
		--tsaurl "${WINDOWS_SIGN_TIMESTAMP_URL:-http://timestamp.digicert.com}")
	mode="certificate file"
else
	fail "Windows signing requested (WINDOWS_SIGN=1) but neither AZURE_SIGNING_ENDPOINT nor WINDOWS_SIGN_PFX_BASE64 is set."
fi

java -jar "$jar" sign "${args[@]}" "$FILE" || fail "jsign could not sign $FILE ($mode)."
echo "Signed $(basename "$FILE") with $mode."
