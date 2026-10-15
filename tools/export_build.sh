#!/usr/bin/env bash
# Exports Soulwick for Windows and Linux into builds/<env>/<version>/ and zips each build (MP4).
#
#   tools/export_build.sh [development|production] [version] [platforms]
#   tools/export_build.sh development                 # version from project.godot, windows + linux
#   tools/export_build.sh production 0.9.0 linux
#
# env selects API and relay addresses (online/environment.cfg, restored afterwards; platform P-018).
# version must equal application/config/version in project.godot. The dev key is never packed
# (docs/MULTIPLAYER.md §3d). Stops before exporting when the export templates are missing.
# Environment: GODOT (Godot binary, default "godot"), TEMPLATE_VERSION (default 4.7.2.stable),
# SKIP_BOOT_TEST=1 (no headless start of the exported Linux/Windows binary on a matching host).
set -euo pipefail

ENVIRONMENT="${1:-development}"
VERSION="${2:-}"
PLATFORMS="${3:-windows linux}"
GODOT="${GODOT:-godot}"
TEMPLATE_VERSION="${TEMPLATE_VERSION:-4.7.2.stable}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/online/environment.cfg"

case "$ENVIRONMENT" in
	development|production) ;;
	*) echo "env must be development or production, not '$ENVIRONMENT'." >&2; exit 1 ;;
esac

PROJECT_VERSION="$(sed -n 's/^config\/version="\([^"]*\)".*/\1/p' "$ROOT/project.godot" | head -n 1)"
if [ -z "$PROJECT_VERSION" ]; then
	echo "project.godot has no application/config/version." >&2
	exit 1
fi
VERSION="${VERSION:-$PROJECT_VERSION}"
if [ "$VERSION" != "$PROJECT_VERSION" ]; then
	echo "Version $VERSION differs from project.godot ($PROJECT_VERSION). Set application/config/version first." >&2
	exit 1
fi

preset_of() { case "$1" in windows) echo "Windows Desktop" ;; linux) echo "Linux" ;; esac; }
binary_of() { case "$1" in windows) echo "Soulwick.exe" ;; linux) echo "Soulwick.x86_64" ;; esac; }
template_of() { case "$1" in windows) echo "windows_release_x86_64.exe" ;; linux) echo "linux_release.x86_64" ;; esac; }

# Export templates live in Godot's data folder of this OS.
if [ -n "${APPDATA:-}" ]; then
	TEMPLATE_DIR="$APPDATA/Godot/export_templates/$TEMPLATE_VERSION"
elif [ "$(uname)" = "Darwin" ]; then
	TEMPLATE_DIR="$HOME/Library/Application Support/Godot/export_templates/$TEMPLATE_VERSION"
else
	TEMPLATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$TEMPLATE_VERSION"
fi
missing=0
for platform in $PLATFORMS; do
	if [ -z "$(preset_of "$platform")" ]; then
		echo "Unknown platform '$platform' (windows, linux)." >&2
		exit 1
	fi
	if [ ! -f "$TEMPLATE_DIR/$(template_of "$platform")" ]; then
		echo "Missing export template: $TEMPLATE_DIR/$(template_of "$platform")" >&2
		missing=1
	fi
done
if [ "$missing" -ne 0 ]; then
	echo "Install them once: Godot editor -> Editor -> Manage Export Templates -> Download and Install" >&2
	echo "(or 'Install from File' with Godot_v4.7.2-stable_export_templates.tpz from godotengine.org)." >&2
	exit 2
fi

OUT_DIR="$ROOT/builds/$ENVIRONMENT/$VERSION"
mkdir -p "$OUT_DIR"
# The editor must not import the builds folder.
touch "$ROOT/builds/.gdignore"

ORIGINAL_ENV="$(mktemp)"
cp "$ENV_FILE" "$ORIGINAL_ENV"
restore_env() { cp "$ORIGINAL_ENV" "$ENV_FILE"; rm -f "$ORIGINAL_ENV"; }
trap restore_env EXIT
sed -i.bak "s/^env[[:space:]]*=.*/env=\"$ENVIRONMENT\"/" "$ENV_FILE" && rm -f "$ENV_FILE.bak"

zip_dir() {
	local source_dir="$1" zip_file="$2" python_bin
	rm -f "$zip_file"
	if command -v zip >/dev/null 2>&1; then
		(cd "$source_dir" && zip -q -r "$zip_file" .)
		return
	fi
	python_bin="$(command -v python3 || command -v python)"
	# ZipInfo.from_file keeps the executable bit of the Linux binary.
	"$python_bin" - "$source_dir" "$zip_file" <<'PY'
import os, sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as archive:
    for name in sorted(os.listdir(src)):
        path = os.path.join(src, name)
        info = zipfile.ZipInfo.from_file(path, name)
        info.compress_type = zipfile.ZIP_DEFLATED
        with open(path, "rb") as handle:
            archive.writestr(info, handle.read())
PY
}

ZIPS=()
for platform in $PLATFORMS; do
	preset="$(preset_of "$platform")"
	platform_dir="$OUT_DIR/$platform"
	binary="$platform_dir/$(binary_of "$platform")"
	rm -rf "$platform_dir"
	mkdir -p "$platform_dir"
	echo "Exporting $preset ($ENVIRONMENT, $VERSION) -> $binary"
	"$GODOT" --headless --path "$ROOT" --export-release "$preset" "$binary"
	if [ ! -f "$binary" ]; then
		echo "Export of $preset failed." >&2
		exit 1
	fi
	sed -e "s/{version}/$VERSION/g" -e "s/{env}/$ENVIRONMENT/g" "$ROOT/tools/build_readme.txt" > "$platform_dir/LIESMICH.txt"
	chmod +x "$binary" 2>/dev/null || true

	# Boot check where the binary can run on this host, with its own user folder.
	host_platform="linux"
	case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) host_platform="windows" ;; Darwin) host_platform="macos" ;; esac
	if [ "${SKIP_BOOT_TEST:-0}" != "1" ] && [ "$platform" = "$host_platform" ]; then
		boot_data="$OUT_DIR/.boot_userdata"
		mkdir -p "$boot_data"
		boot_log="$(APPDATA="$boot_data" XDG_DATA_HOME="$boot_data" "$binary" --headless --quit-after 300 -- offline 2>&1)" || {
			echo "$boot_log"; rm -rf "$boot_data"; echo "The exported binary did not boot cleanly." >&2; exit 1; }
		rm -rf "$boot_data"
		echo "$boot_log"
		if echo "$boot_log" | grep -Eq "SCRIPT ERROR|Parse Error|Failed to load"; then
			echo "The exported binary reported errors while booting (see above)." >&2
			exit 1
		fi
		echo "Boot check passed."
	fi

	zip_file="$OUT_DIR/Soulwick-$VERSION-$ENVIRONMENT-$platform.zip"
	zip_dir "$platform_dir" "$zip_file"
	ZIPS+=("$zip_file")
done

echo "Done:"
printf '  %s\n' "${ZIPS[@]}"
