#!/usr/bin/env bash
# Uploads an Android App Bundle to a Google Play test track over the Google Play Developer API
# (release.yml job "android-aab", docs/STORES.md "Google Play"). No third-party action: a service
# account key signs a JWT (openssl), the access token opens an "edit", the bundle is uploaded, the
# track gets a release with that versionCode, the edit is committed.
#
#   tools/ci/play_upload.sh builds/<env>/<version>/Soulwick-<v>-<env>-android.aab
#
# Environment:
#   PLAY_SERVICE_ACCOUNT_JSON  JSON key of the service account (as is or base64), secret
#   PLAY_TRACK                 internal (default), alpha (closed), beta (open), production
#   PLAY_RELEASE_STATUS        completed (default) or draft (needed while the app itself is still a
#                              draft in the Play Console; then release it there by hand)
#   PLAY_RELEASE_NAME          shown in the Play Console (default: versionName (versionCode))
#   PACKAGE                    default com.webbude.soulwick
# Needs curl, jq, openssl. The first bundle of a new app must be uploaded by hand once.
set -euo pipefail

AAB="${1:?usage: play_upload.sh <aab>}"
PACKAGE="${PACKAGE:-com.webbude.soulwick}"
TRACK="${PLAY_TRACK:-internal}"
STATUS="${PLAY_RELEASE_STATUS:-completed}"
API="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$PACKAGE"
UPLOAD_API="https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/$PACKAGE"
WORK="$(mktemp -d)"
chmod 700 "$WORK"
edit_id=""
token=""

fail() {
	echo "::error::$1" >&2
	exit 1
}

cleanup() {
	# An edit that was not committed is thrown away, so the next run starts clean.
	if [ -n "$edit_id" ] && [ -n "$token" ]; then
		curl -fsS -X DELETE -H "Authorization: Bearer $token" "$API/edits/$edit_id" >/dev/null 2>&1 || true
	fi
	rm -rf "$WORK"
}
trap cleanup EXIT

[ -f "$AAB" ] || fail "$AAB does not exist."
[ -n "${PLAY_SERVICE_ACCOUNT_JSON:-}" ] || fail "PLAY_SERVICE_ACCOUNT_JSON is missing."
case "$TRACK" in internal|alpha|beta|production) ;; *) fail "PLAY_TRACK must be internal, alpha, beta or production." ;; esac
case "$STATUS" in completed|draft) ;; *) fail "PLAY_RELEASE_STATUS must be completed or draft." ;; esac
for tool in curl jq openssl; do
	command -v "$tool" >/dev/null 2>&1 || fail "play_upload.sh needs $tool."
done

key_json="$WORK/key.json"
if printf '%s' "$PLAY_SERVICE_ACCOUNT_JSON" | jq -e . >/dev/null 2>&1; then
	printf '%s' "$PLAY_SERVICE_ACCOUNT_JSON" > "$key_json"
else
	printf '%s' "$PLAY_SERVICE_ACCOUNT_JSON" | tr -d '\r\n ' | base64 -d > "$key_json" 2>/dev/null ||
		fail "PLAY_SERVICE_ACCOUNT_JSON is neither JSON nor base64 of the JSON key."
fi
client_email="$(jq -r '.client_email // empty' "$key_json")"
token_uri="$(jq -r '.token_uri // "https://oauth2.googleapis.com/token"' "$key_json")"
jq -r '.private_key // empty' "$key_json" > "$WORK/key.pem"
if [ -z "$client_email" ] || [ ! -s "$WORK/key.pem" ]; then
	fail "PLAY_SERVICE_ACCOUNT_JSON has no client_email/private_key (JSON key of a service account)."
fi

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
now="$(date +%s)"
header="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)"
claims="$(jq -cn --arg iss "$client_email" --arg aud "$token_uri" --argjson iat "$now" \
	'{iss: $iss, scope: "https://www.googleapis.com/auth/androidpublisher", aud: $aud, iat: $iat, exp: ($iat + 3600)}' | b64url)"
signature="$(printf '%s.%s' "$header" "$claims" | openssl dgst -sha256 -sign "$WORK/key.pem" -binary | b64url)" ||
	fail "openssl could not sign with the service account key."
rm -f "$WORK/key.pem" "$key_json"

response="$(curl -sS -X POST "$token_uri" --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer" \
	--data-urlencode "assertion=$header.$claims.$signature")"
token="$(printf '%s' "$response" | jq -r '.access_token // empty')"
[ -n "$token" ] || fail "Google rejected the service account: $(printf '%s' "$response" | jq -c '{error, error_description}' 2>/dev/null)"
[ -n "${GITHUB_ACTIONS:-}" ] && echo "::add-mask::$token"

# call <method> <url> [curl args...] -> JSON body on stdout, fails with Google's message.
call() {
	local method="$1" url="$2" body status
	shift 2
	body="$WORK/response.json"
	status="$(curl -sS -o "$body" -w '%{http_code}' -X "$method" -H "Authorization: Bearer $token" "$@" "$url")"
	if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
		echo "Google Play API $method $url -> HTTP $status" >&2
		jq -r '.error.message // .' "$body" >&2 2>/dev/null || cat "$body" >&2
		return 1
	fi
	cat "$body"
}

edit_id="$(call POST "$API/edits" -H "Content-Type: application/json" -d '{}' | jq -r '.id')" ||
	fail "Could not open an edit (is the service account invited in the Play Console with release rights, and does the app $PACKAGE exist?)."
echo "Uploading $(basename "$AAB") ($(du -h "$AAB" | cut -f1)) ..."
bundle="$(call POST "$UPLOAD_API/edits/$edit_id/bundles?uploadType=media" \
	-H "Content-Type: application/octet-stream" --data-binary "@$AAB")" ||
	fail "Upload refused (a versionCode can be used only once: raise the version, docs/STORES.md)."
version_code="$(printf '%s' "$bundle" | jq -r '.versionCode')"
release_name="${PLAY_RELEASE_NAME:-${VERSION:-} ($version_code)}"
release="$(jq -cn --arg track "$TRACK" --arg name "$release_name" --arg code "$version_code" --arg status "$STATUS" \
	'{track: $track, releases: [{name: $name, versionCodes: [$code], status: $status}]}')"
call PUT "$API/edits/$edit_id/tracks/$TRACK" -H "Content-Type: application/json" -d "$release" >/dev/null ||
	fail "Could not put versionCode $version_code on the track '$TRACK'."
call POST "$API/edits/$edit_id:commit" -d '' >/dev/null || fail "Commit of the edit failed (see above)."
edit_id=""
echo "Google Play: versionCode $version_code is on the track '$TRACK' ($STATUS)."
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	echo "### Google Play: versionCode $version_code on '$TRACK' ($STATUS)" >> "$GITHUB_STEP_SUMMARY"
fi
