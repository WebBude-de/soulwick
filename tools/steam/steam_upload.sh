#!/usr/bin/env bash
# Uploads the release zips of Windows, Linux and macOS to Steam with steamcmd (SteamPipe) and sets
# the build live on a beta branch (release.yml job "steam", docs/STORES.md "Steam"). Linux runner.
# Only build and upload: Steamworks in the game (GodotSteam, lobbies, achievements) is MP6/MP10.
#
#   tools/steam/steam_upload.sh <folder with Soulwick-<v>-<env>-{windows,linux,macos}.zip>
#
# Environment:
#   STEAM_USERNAME     Steam build account (own account with only the "Edit App Metadata" and
#                      "Publish App Changes To Steam" rights for this app), secret
#   STEAM_CONFIG_VDF   base64 of config/config.vdf after one steamcmd login with Steam Guard, secret
#   STEAM_APP_ID       App ID (repository variable), required
#   STEAM_DEPOT_WINDOWS, STEAM_DEPOT_LINUX, STEAM_DEPOT_MACOS   depot IDs (default App ID + 1/2/3)
#   STEAM_BRANCH       branch to set live, default "beta" ("" = upload only, set live by hand)
#   STEAM_PREVIEW=1    dry run (steamcmd checks everything, uploads nothing)
#   VERSION, ENVIRONMENT, TAG   for the build description
set -euo pipefail

DIST="${1:?usage: steam_upload.sh <folder with the release zips>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${RUNNER_TEMP:-$(mktemp -d)}/steam"
STEAMCMD_DIR="${STEAMCMD_DIR:-$WORK/steamcmd}"
STEAMCMD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"

fail() {
	echo "::error::$1" >&2
	exit 1
}

cleanup() {
	# The login token never stays on the runner.
	rm -f "$STEAMCMD_DIR/config/config.vdf" "$HOME/Steam/config/config.vdf"
}
trap cleanup EXIT

for name in STEAM_USERNAME STEAM_CONFIG_VDF STEAM_APP_ID; do
	[ -n "${!name:-}" ] || fail "Steam upload: $name is missing (docs/STORES.md, Steam)."
done
case "$STEAM_APP_ID" in *[!0-9]*) fail "STEAM_APP_ID must be a number." ;; esac
STEAM_DEPOT_WINDOWS="${STEAM_DEPOT_WINDOWS:-$((STEAM_APP_ID + 1))}"
STEAM_DEPOT_LINUX="${STEAM_DEPOT_LINUX:-$((STEAM_APP_ID + 2))}"
STEAM_DEPOT_MACOS="${STEAM_DEPOT_MACOS:-$((STEAM_APP_ID + 3))}"
for name in STEAM_DEPOT_WINDOWS STEAM_DEPOT_LINUX STEAM_DEPOT_MACOS; do
	case "${!name}" in ''|*[!0-9]*) fail "$name must be a number." ;; esac
done
STEAM_BRANCH="${STEAM_BRANCH-beta}"
[ "$STEAM_BRANCH" != "default" ] || fail "SteamPipe may not set the default branch live; a human does that in Steamworks."
case "$STEAM_BRANCH" in *[!A-Za-z0-9_-]*) fail "STEAM_BRANCH may only contain letters, digits, - and _." ;; esac
STEAM_PREVIEW="${STEAM_PREVIEW:-0}"
case "$STEAM_PREVIEW" in 0|1) ;; *) fail "STEAM_PREVIEW must be 0 or 1." ;; esac
# Description: only harmless characters (it lands in a VDF string). Read by render() via ${!key}.
# shellcheck disable=SC2034
BUILD_DESC="$(printf 'Soulwick %s %s %s' "${VERSION:-?}" "${ENVIRONMENT:-?}" "${TAG:-}" | tr -cd 'A-Za-z0-9 ._()+-' | sed 's/ *$//')"

# Content: each release zip unpacked into its own depot folder.
CONTENT_ROOT="$WORK/content"
BUILD_OUTPUT="$WORK/output"
rm -rf "$CONTENT_ROOT" "$BUILD_OUTPUT"
mkdir -p "$CONTENT_ROOT" "$BUILD_OUTPUT" "$WORK/scripts"
for platform in windows linux macos; do
	zip_file="$(find "$DIST" -maxdepth 1 -name "Soulwick-*-$platform.zip" | head -n 1)"
	[ -n "$zip_file" ] || fail "No Soulwick-*-$platform.zip in $DIST."
	mkdir -p "$CONTENT_ROOT/$platform"
	unzip -q "$zip_file" -d "$CONTENT_ROOT/$platform"
done
[ -x "$CONTENT_ROOT/linux/Soulwick.x86_64" ] || fail "Linux depot: Soulwick.x86_64 is missing or not executable."
[ -f "$CONTENT_ROOT/windows/Soulwick.exe" ] || fail "Windows depot: Soulwick.exe is missing."
[ -d "$CONTENT_ROOT/macos/Soulwick.app" ] || fail "macOS depot: Soulwick.app is missing."

# Templates -> scripts (pure bash replacement of ${NAME}; no eval).
render() {
	local template="$1" text key
	text="$(cat "$template")"
	shift 2
	for key in "$@"; do
		text="${text//\$\{$key\}/${!key}}"
	done
	# Placeholders left outside the comments mean a key is missing above.
	# shellcheck disable=SC2016
	if grep -v '^[[:space:]]*//' <<< "$text" | grep -q '\${'; then
		fail "Unfilled placeholder in $(basename "$template")."
	fi
	printf '%s\n' "$text"
}
app_vdf="$WORK/scripts/app_build_$STEAM_APP_ID.vdf"
render "$HERE/app_build.vdf" -- STEAM_APP_ID BUILD_DESC CONTENT_ROOT BUILD_OUTPUT STEAM_BRANCH STEAM_PREVIEW \
	STEAM_DEPOT_WINDOWS STEAM_DEPOT_LINUX STEAM_DEPOT_MACOS > "$app_vdf"
# DEPOT_ID and DEPOT_CONTENT are read by render() via ${!key}.
# shellcheck disable=SC2034
for platform in windows linux macos; do
	case "$platform" in
		windows) DEPOT_ID="$STEAM_DEPOT_WINDOWS" ;;
		linux) DEPOT_ID="$STEAM_DEPOT_LINUX" ;;
		macos) DEPOT_ID="$STEAM_DEPOT_MACOS" ;;
	esac
	DEPOT_CONTENT="$CONTENT_ROOT/$platform"
	render "$HERE/depot_build.vdf" -- DEPOT_ID DEPOT_CONTENT > "$WORK/scripts/depot_build_$platform.vdf"
done
echo "App build script:"
grep -v '^//' "$app_vdf"

# steamcmd (32 bit, needs lib32gcc-s1 on Ubuntu).
if [ ! -x "$STEAMCMD_DIR/steamcmd.sh" ]; then
	if command -v dpkg >/dev/null 2>&1 && ! dpkg -s lib32gcc-s1 >/dev/null 2>&1; then
		sudo apt-get update -qq && sudo apt-get install -y -qq lib32gcc-s1 >/dev/null
	fi
	mkdir -p "$STEAMCMD_DIR"
	curl -fsSL --retry 3 "$STEAMCMD_URL" | tar -xz -C "$STEAMCMD_DIR"
fi
for dir in "$STEAMCMD_DIR/config" "$HOME/Steam/config"; do
	mkdir -p "$dir"
	printf '%s' "$STEAM_CONFIG_VDF" | tr -d '\r\n ' | base64 -d > "$dir/config.vdf" 2>/dev/null ||
		fail "STEAM_CONFIG_VDF is not valid base64 of config.vdf."
	chmod 600 "$dir/config.vdf"
done

log="$WORK/steamcmd.log"
status=0
"$STEAMCMD_DIR/steamcmd.sh" +@ShutdownOnFailedCommand 1 +@NoPromptForPassword 1 \
	+login "$STEAM_USERNAME" +run_app_build "$app_vdf" +quit 2>&1 | tee "$log" || status=$?
if [ "$status" -ne 0 ] || ! grep -q "Successfully finished AppID" "$log"; then
	if grep -qiE "Steam Guard|Two-factor|Invalid Password|rate limit|Login Failure" "$log"; then
		echo "::error::Steam login failed: renew STEAM_CONFIG_VDF (docs/STORES.md, Steam, config.vdf)." >&2
	fi
	for file in "$STEAMCMD_DIR/logs/stderr.txt" "$BUILD_OUTPUT"/*.log; do
		[ -f "$file" ] && { echo "--- $file"; tail -n 40 "$file"; }
	done
	fail "steamcmd run_app_build failed (exit $status)."
fi
build_id="$(sed -n 's/.*Successfully finished AppID [0-9]* build (BuildID \([0-9]*\)).*/\1/p' "$log" | tail -n 1)"
live=""
[ -n "$STEAM_BRANCH" ] && live=", live on branch $STEAM_BRANCH"
echo "Steam: build ${build_id:-?} uploaded$live."
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	echo "### Steam: build ${build_id:-?} (App $STEAM_APP_ID)${STEAM_BRANCH:+ on branch \`$STEAM_BRANCH\`}" >> "$GITHUB_STEP_SUMMARY"
fi
