#!/usr/bin/env bash
# Runs Godot with a real window, but on an invisible virtual screen (Linux with KDE/KWin), so
# window tools (screenshots.gd, scene_gallery.gd, side_check.gd …) don't pop up on the desktop.
# Always silent (dummy audio driver).
# Usage, like godot itself:  tools/godot_offscreen.sh --path . -s tools/screenshots.gd -- <folder>
# GODOT overrides the binary (default: godot in PATH), OFFSCREEN_SIZE the screen (default 1920x1080).
set -euo pipefail

godot_bin="${GODOT:-godot}"
size="${OFFSCREEN_SIZE:-1920x1080}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# KWin runs this inner script as its session and quits when it ends; the exit code goes via a file.
{
	printf '#!/usr/bin/env bash\n'
	printf 'unset DISPLAY\n'
	printf '%q --display-driver wayland --audio-driver Dummy' "$godot_bin"
	printf ' %q' "$@"
	printf '\necho $? > %q\n' "$work/exit_code"
} > "$work/session.sh"
chmod +x "$work/session.sh"

kwin_wayland --virtual --no-lockscreen --width "${size%x*}" --height "${size#*x}" \
	--socket "godot-offscreen-$$" --exit-with-session "$work/session.sh" \
	2> >(grep -v -E '^(kwin_|kf\.|qt\.|QSocketNotifier|Failed to|xkbcommon)' >&2)

exit "$(cat "$work/exit_code" 2>/dev/null || echo 1)"
