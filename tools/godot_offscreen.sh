#!/usr/bin/env bash
# Runs Godot with a real window and a real renderer, but inside a private headless Wayland
# compositor (Linux), so window tools (screenshots.gd, scene_gallery.gd, side_check.gd …)
# don't pop up on the desktop. Always silent (dummy audio driver).
# Usage, like godot itself:  tools/godot_offscreen.sh --path . -s tools/screenshots.gd -- <folder>
#
# Compositor: cage (preferred) or weston, both with their headless backend and a GPU renderer.
# Install one of them: `sudo dnf install cage` (or `weston`); apt/pacman have the same names.
# Never use a second kwin_wayland (not even --virtual) for this: when it quits it marks all
# KWin global shortcuts of the running Plasma session as inactive (Alt+Tab, Super+Tab …).
#
# Environment:
#   GODOT                 Godot binary (default: godot in PATH)
#   OFFSCREEN_COMPOSITOR  cage | weston (default: the first one found)
#   OFFSCREEN_SIZE        screen size for weston (default 1920x1080); cage always uses 1280x720
#   WLR_RENDERER          renderer for cage (default gles2; vulkan also works)
set -euo pipefail

godot_bin="${GODOT:-godot}"
size="${OFFSCREEN_SIZE:-1920x1080}"
socket="godot-offscreen-$$"

compositor="${OFFSCREEN_COMPOSITOR:-}"
if [[ -z "$compositor" ]]; then
	for candidate in cage weston; do
		if command -v "$candidate" > /dev/null; then
			compositor="$candidate"
			break
		fi
	done
fi
case "$compositor" in
	cage | weston)
		if ! command -v "$compositor" > /dev/null; then
			echo "godot_offscreen: '$compositor' is not installed." >&2
			exit 127
		fi
		;;
	"")
		echo "godot_offscreen: no headless compositor found." >&2
		echo "  Install cage (or weston), e.g. 'sudo dnf install cage', then run this again." >&2
		echo "  (kwin_wayland is deliberately not used: it breaks the KWin shortcuts of the session.)" >&2
		exit 127
		;;
	*)
		echo "godot_offscreen: unsupported OFFSCREEN_COMPOSITOR '$compositor' (use cage or weston)." >&2
		exit 2
		;;
esac

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The compositor runs this inner script and quits when it ends; the exit code goes via a file.
# Godot writes to fd 3/4 (this script's stdout/stderr), the compositor's own noise goes to a log.
{
	printf '#!/usr/bin/env bash\n'
	printf 'if { true >&3; } 2> /dev/null; then exec 1>&3 2>&4; fi\n'
	printf 'exec 3>&- 4>&-\n'
	printf 'unset DISPLAY\n'
	printf '%q --display-driver wayland --audio-driver Dummy' "$godot_bin"
	printf ' %q' "$@"
	printf '\necho $? > %q\n' "$work/exit_code"
} > "$work/session.sh"
chmod +x "$work/session.sh"

log="$work/compositor.log"
status=0
case "$compositor" in
	cage)
		# -d: no server-side decorations. The headless output is fixed at 1280x720 by wlroots.
		env -u WAYLAND_DISPLAY -u DISPLAY \
			WLR_BACKENDS=headless WLR_RENDERER="${WLR_RENDERER:-gles2}" \
			cage -d -- "$work/session.sh" 3>&1 4>&2 > "$log" 2>&1 || status=$?
		;;
	weston)
		# [autolaunch] watch=true: weston quits when the session script ends.
		printf '[core]\nidle-time=0\n\n[autolaunch]\npath=%s\nwatch=true\n' \
			"$work/session.sh" > "$work/weston.ini"
		env -u WAYLAND_DISPLAY -u DISPLAY \
			weston --backend=headless --renderer=gl --config="$work/weston.ini" \
			--width="${size%x*}" --height="${size#*x}" --idle-time=0 --socket="$socket" \
			--log="$log" 3>&1 4>&2 > /dev/null 2>&1 || status=$?
		;;
esac

if [[ ! -s "$work/exit_code" ]]; then
	echo "godot_offscreen: $compositor ended (status $status) without running Godot. Its log:" >&2
	tail -n 30 "$log" >&2 || true
	exit 1
fi
exit "$(cat "$work/exit_code")"
