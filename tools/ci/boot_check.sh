#!/usr/bin/env bash
# Boot check of a released Linux zip (release.yml): unpacks it like a player would, starts
# Soulwick.x86_64 headless and without sound for 300 frames in offline mode, with its own user
# folder, and fails on script or load errors. Same check as tools/export_build.* run on the binary,
# but on the zip that goes into the release (also catches a lost executable bit).
#
#   tools/ci/boot_check.sh builds/development/0.9.1/Soulwick-0.9.1-development-linux.zip
set -euo pipefail

ZIP="${1:?usage: boot_check.sh <linux zip>}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

unzip -q "$ZIP" -d "$WORK/game"
binary="$WORK/game/Soulwick.x86_64"
if [ ! -x "$binary" ]; then
	echo "::error::Soulwick.x86_64 is missing in $ZIP or not executable." >&2
	exit 1
fi

mkdir -p "$WORK/userdata"
status=0
log="$(XDG_DATA_HOME="$WORK/userdata" timeout 180 "$binary" --headless --audio-driver Dummy --quit-after 300 -- offline 2>&1)" || status=$?
echo "$log"
if [ "$status" -ne 0 ]; then
	echo "::error::The exported Linux build did not boot cleanly (exit $status)." >&2
	exit 1
fi
# Here-string: with pipefail, "echo | grep -q" on a long log can fail with SIGPIPE.
if grep -Eq "SCRIPT ERROR|Parse Error|Failed to load" <<< "$log"; then
	echo "::error::The exported Linux build reported errors while booting (see above)." >&2
	exit 1
fi
echo "Boot check passed: $ZIP"
