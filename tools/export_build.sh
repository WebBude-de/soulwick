#!/usr/bin/env bash
# Exports Soulwick into builds/<env>/<version>/ (docs/RELEASE.md, docs/STORES.md):
#   windows, linux  Soulwick-<version>-<env>-<platform>.zip (folder with binary + LIESMICH.txt; MP4)
#   macos           Soulwick-<version>-<env>-macos.zip (universal Soulwick.app, ad-hoc signed, not
#                   notarized; tools/ci/macos_sign.sh signs and notarizes it on a Mac)
#   web             folder web/ (index.html, single-threaded, no COOP/COEP headers) plus its zip
#   android         Soulwick-<version>-<env>.apk (no Gradle; CP2/CP7, to install by hand)
#   android-aab     Soulwick-<version>-<env>-android.aab (Gradle build for Google Play; installs the
#                   Android build template into android/ and removes it again if it was not there)
#   ios             folder ios/ (Xcode project) plus Soulwick-<version>-<env>-ios-xcode.zip; the
#                   signed .ipa comes from tools/ci/ios_build.sh on a Mac
# Only windows and linux get a boot check (on a matching host).
#
#   tools/export_build.sh [development|production] [version] [platforms]
#   tools/export_build.sh development                 # version from project.godot, windows + linux
#   tools/export_build.sh production 0.9.0 linux
#   tools/export_build.sh development "" android
#   tools/export_build.sh production "" "windows linux macos"   # what the release workflow builds
#   tools/export_build.sh development "" "android-aab ios"       # store formats
#
# env selects API and relay addresses (online/environment.cfg, restored afterwards; platform P-018).
# version must equal application/config/version in project.godot. The dev key is never packed
# (docs/MULTIPLAYER.md §3d). Stops before exporting when the export templates are missing.
# "android-aab" and "ios" need the presets "Android AAB" and "iOS": tools/ci/store_presets.py adds
# them to export_presets.cfg for the export; the file is restored afterwards like environment.cfg.
#
# Environment:
#   GODOT             Godot binary (default "godot"); TEMPLATE_VERSION (default 4.7.2.stable)
#   SKIP_BOOT_TEST=1  no headless start of the exported Linux/Windows binary
#   VERSION_CODE      Android versionCode and iOS build number; default from the version
#                     (0.9.1 -> 901). The release workflow passes a bigger one for the stores.
#   WINDOWS_SIGN=1    signs Soulwick.exe with tools/ci/sign_windows.sh before zipping
#   APPLE_TEAM_ID     team ID for the Xcode project (otherwise a placeholder)
#   KEEP_ANDROID_BUILD=1  keeps a freshly installed android/ folder after an AAB export
# Android: JDK 17 and the Android SDK (Godot takes JAVA_HOME and ANDROID_HOME, or the editor
# settings); signed with GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD, for development builds
# otherwise with the local debug keystore (Godot data folder/keystores/debug.keystore). Never put
# keys in the repo.
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

preset_of() { case "$1" in windows) echo "Windows Desktop" ;; linux) echo "Linux" ;; macos) echo "macOS" ;; web) echo "Web" ;; android) echo "Android" ;; android-aab) echo "Android AAB" ;; ios) echo "iOS" ;; esac; }
binary_of() { case "$1" in windows) echo "Soulwick.exe" ;; linux) echo "Soulwick.x86_64" ;; esac; }
template_of() { case "$1" in windows) echo "windows_release_x86_64.exe" ;; linux) echo "linux_release.x86_64" ;; macos) echo "macos.zip" ;; web) echo "web_nothreads_release.zip" ;; android) echo "android_release.apk" ;; android-aab) echo "android_source.zip" ;; ios) echo "ios.zip" ;; esac; }

# Export templates (and the debug keystore) live in Godot's data folder of this OS.
if [ -n "${APPDATA:-}" ]; then
	GODOT_DATA="$APPDATA/Godot"
elif [ "$(uname)" = "Darwin" ]; then
	GODOT_DATA="$HOME/Library/Application Support/Godot"
else
	GODOT_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/godot"
fi
TEMPLATE_DIR="$GODOT_DATA/export_templates/$TEMPLATE_VERSION"
missing=0
store_presets=()
for platform in $PLATFORMS; do
	if [ -z "$(preset_of "$platform")" ]; then
		echo "Unknown platform '$platform' (windows, linux, macos, web, android, android-aab, ios)." >&2
		exit 1
	fi
	if [ ! -f "$TEMPLATE_DIR/$(template_of "$platform")" ]; then
		echo "Missing export template: $TEMPLATE_DIR/$(template_of "$platform")" >&2
		missing=1
	fi
	case "$platform" in android-aab|ios) store_presets+=("$platform") ;; esac
done
if [ "$missing" -ne 0 ]; then
	echo "Install them once: Godot editor -> Editor -> Manage Export Templates -> Download and Install" >&2
	echo "(or 'Install from File' with Godot_v4.7.2-stable_export_templates.tpz from godotengine.org)." >&2
	exit 2
fi

# Android versionCode / iOS build number: grows with every version, so phones accept the update.
if [ -n "${VERSION_CODE:-}" ]; then
	case "$VERSION_CODE" in *[!0-9]*|"") echo "VERSION_CODE must be a whole number." >&2; exit 1 ;; esac
	version_code="$VERSION_CODE"
else
	version_code="$(echo "$VERSION" | awk -F'[^0-9]+' '{ code = $1 * 10000 + $2 * 100 + $3; print (code < 1 ? 1 : code) }')"
fi

OUT_DIR="$ROOT/builds/$ENVIRONMENT/$VERSION"
mkdir -p "$OUT_DIR"
# The editor must not import the builds folder.
touch "$ROOT/builds/.gdignore"

PRESETS_FILE="$ROOT/export_presets.cfg"
ANDROID_DIR="$ROOT/android"
ANDROID_DIR_EXISTED=0
[ -e "$ANDROID_DIR" ] && ANDROID_DIR_EXISTED=1
ORIGINAL_ENV="$(mktemp)"
ORIGINAL_PRESETS="$(mktemp)"
BASE_PRESETS="$(mktemp)"
cp "$ENV_FILE" "$ORIGINAL_ENV"
cp "$PRESETS_FILE" "$ORIGINAL_PRESETS"
restore_env() {
	cp "$ORIGINAL_ENV" "$ENV_FILE"
	cmp -s "$ORIGINAL_PRESETS" "$PRESETS_FILE" || cp "$ORIGINAL_PRESETS" "$PRESETS_FILE"
	rm -f "$ORIGINAL_ENV" "$ORIGINAL_PRESETS" "$BASE_PRESETS"
	# android/ is generated from the template (Godot's own .gitignore ignores it); leave no trace.
	if [ "$ANDROID_DIR_EXISTED" = "0" ] && [ -d "$ANDROID_DIR" ] && [ "${KEEP_ANDROID_BUILD:-0}" != "1" ]; then
		rm -rf "$ANDROID_DIR"
	fi
}
trap restore_env EXIT
sed -i.bak "s/^env[[:space:]]*=.*/env=\"$ENVIRONMENT\"/" "$ENV_FILE" && rm -f "$ENV_FILE.bak"

# First Python 3 that really runs (on Windows "python3" can be the Microsoft Store stub).
python_bin() {
	local candidate
	for candidate in python3 python; do
		if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "" >/dev/null 2>&1; then
			echo "$candidate"
			return
		fi
	done
	echo "Python 3 not found (needed to write zips and store presets)." >&2
	return 1
}

if [ "${#store_presets[@]}" -gt 0 ]; then
	BUILD_NUMBER="$version_code" "$(python_bin)" "$ROOT/tools/ci/store_presets.py" "$PRESETS_FILE" "${store_presets[@]}"
fi
# Presets as they are for this run; the version code below is only set for one export.
cp "$PRESETS_FILE" "$BASE_PRESETS"

zip_dir() {
	local source_dir="$1" zip_file="$2" python
	rm -f "$zip_file"
	if command -v zip >/dev/null 2>&1; then
		(cd "$source_dir" && zip -q -r -y "$zip_file" .)
		return
	fi
	python="$(python_bin)"
	# ZipInfo.from_file keeps the executable bit of the Linux binary.
	"$python" - "$source_dir" "$zip_file" <<'PY'
import os, sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as archive:
    for folder, dirs, files in os.walk(src):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(folder, name)
            arcname = os.path.relpath(path, src).replace(os.sep, "/")
            info = zipfile.ZipInfo.from_file(path, arcname)
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(path, "rb") as handle:
                archive.writestr(info, handle.read())
PY
}

# Adds one file to an existing zip without touching its entries (keeps the .app permissions).
add_to_zip() {
	local zip_file="$1" source_file="$2" name="$3" python
	python="$(python_bin)"
	"$python" - "$zip_file" "$source_file" "$name" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "a", zipfile.ZIP_DEFLATED) as archive:
    archive.write(sys.argv[2], sys.argv[3])
PY
}

# Signing key for APK and AAB (the same env variables Godot reads).
android_keystore() {
	if [ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ]; then
		return
	fi
	if [ "$ENVIRONMENT" = "production" ] || [ "$1" = "android-aab" ]; then
		echo "Production APKs and every AAB need the real key: set GODOT_ANDROID_KEYSTORE_RELEASE_PATH, _USER and _PASSWORD." >&2
		exit 1
	fi
	local debug_keystore="$GODOT_DATA/keystores/debug.keystore"
	if [ ! -f "$debug_keystore" ]; then
		mkdir -p "$(dirname "$debug_keystore")"
		keytool -genkeypair -keystore "$debug_keystore" -storepass android -alias androiddebugkey \
			-keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
	fi
	export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$debug_keystore"
	export GODOT_ANDROID_KEYSTORE_RELEASE_USER="androiddebugkey"
	export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="android"
}

ZIPS=()
for platform in $PLATFORMS; do
	preset="$(preset_of "$platform")"
	if [ "$platform" = "android" ] || [ "$platform" = "android-aab" ]; then
		android_keystore "$platform"
		sed -i.bak "s/^version\/code=[0-9]*/version\/code=$version_code/" "$PRESETS_FILE" && rm -f "$PRESETS_FILE.bak"
		extra_args=()
		if [ "$platform" = "android" ]; then
			package="$OUT_DIR/Soulwick-$VERSION-$ENVIRONMENT.apk"
		else
			package="$OUT_DIR/Soulwick-$VERSION-$ENVIRONMENT-android.aab"
			# Fresh template of exactly this Godot version (writes android/build and android/.build_version).
			extra_args+=(--install-android-build-template)
		fi
		rm -f "$package"
		echo "Exporting $preset ($ENVIRONMENT, $VERSION, code $version_code) -> $package"
		"$GODOT" --headless --audio-driver Dummy --path "$ROOT" ${extra_args[@]+"${extra_args[@]}"} --export-release "$preset" "$package"
		cp "$BASE_PRESETS" "$PRESETS_FILE"
		if [ ! -f "$package" ]; then
			echo "Export of $preset failed." >&2
			exit 1
		fi
		# apksigner's v4 side file is only for adb incremental installs; friends get the APK alone.
		rm -f "$package.idsig"
		if [ "$platform" = "android" ]; then
			sed -e "s/{version}/$VERSION/g" -e "s/{env}/$ENVIRONMENT/g" "$ROOT/tools/build_readme_android.txt" > "$OUT_DIR/LIESMICH-android.txt"
		fi
		ZIPS+=("$package")
		continue
	fi
	if [ "$platform" = "ios" ]; then
		# Xcode project only (application/export_project_only): works on every host; archive, signature
		# and .ipa need Xcode (tools/ci/ios_build.sh).
		ios_dir="$OUT_DIR/ios"
		rm -rf "$ios_dir"
		mkdir -p "$ios_dir"
		echo "Exporting $preset ($ENVIRONMENT, $VERSION, build $version_code) -> $ios_dir/Soulwick.xcodeproj"
		"$GODOT" --headless --audio-driver Dummy --path "$ROOT" --export-release "$preset" "$ios_dir/Soulwick.ipa"
		if [ ! -d "$ios_dir/Soulwick.xcodeproj" ]; then
			echo "Export of $preset failed (no Xcode project)." >&2
			exit 1
		fi
		zip_file="$OUT_DIR/Soulwick-$VERSION-$ENVIRONMENT-ios-xcode.zip"
		zip_dir "$ios_dir" "$zip_file"
		ZIPS+=("$zip_file")
		continue
	fi
	if [ "$platform" = "macos" ]; then
		# Godot writes Soulwick.app into the zip itself (on every host); the readme is added to it.
		zip_file="$OUT_DIR/Soulwick-$VERSION-$ENVIRONMENT-macos.zip"
		rm -f "$zip_file"
		echo "Exporting $preset ($ENVIRONMENT, $VERSION) -> $zip_file"
		"$GODOT" --headless --audio-driver Dummy --path "$ROOT" --export-release "$preset" "$zip_file"
		if [ ! -f "$zip_file" ]; then
			echo "Export of $preset failed." >&2
			exit 1
		fi
		readme="$(mktemp)"
		sed -e "s/{version}/$VERSION/g" -e "s/{env}/$ENVIRONMENT/g" "$ROOT/tools/build_readme.txt" > "$readme"
		add_to_zip "$zip_file" "$readme" "LIESMICH.txt"
		rm -f "$readme"
		ZIPS+=("$zip_file")
		continue
	fi
	if [ "$platform" = "web" ]; then
		# The folder is what a web server serves; the zip is the release asset.
		web_dir="$OUT_DIR/web"
		rm -rf "$web_dir"
		mkdir -p "$web_dir"
		echo "Exporting $preset ($ENVIRONMENT, $VERSION) -> $web_dir/index.html"
		"$GODOT" --headless --audio-driver Dummy --path "$ROOT" --export-release "$preset" "$web_dir/index.html"
		if [ ! -f "$web_dir/index.html" ] || [ ! -f "$web_dir/index.pck" ]; then
			echo "Export of $preset failed." >&2
			exit 1
		fi
		zip_file="$OUT_DIR/Soulwick-$VERSION-$ENVIRONMENT-web.zip"
		zip_dir "$web_dir" "$zip_file"
		ZIPS+=("$zip_file")
		continue
	fi
	platform_dir="$OUT_DIR/$platform"
	binary="$platform_dir/$(binary_of "$platform")"
	rm -rf "$platform_dir"
	mkdir -p "$platform_dir"
	echo "Exporting $preset ($ENVIRONMENT, $VERSION) -> $binary"
	"$GODOT" --headless --audio-driver Dummy --path "$ROOT" --export-release "$preset" "$binary"
	if [ ! -f "$binary" ]; then
		echo "Export of $preset failed." >&2
		exit 1
	fi
	sed -e "s/{version}/$VERSION/g" -e "s/{env}/$ENVIRONMENT/g" "$ROOT/tools/build_readme.txt" > "$platform_dir/LIESMICH.txt"
	chmod +x "$binary" 2>/dev/null || true
	if [ "$platform" = "windows" ] && [ "${WINDOWS_SIGN:-0}" = "1" ]; then
		# Authenticode signature (Godot puts the .pck into its own PE section, so signing keeps it).
		bash "$ROOT/tools/ci/sign_windows.sh" "$binary"
	fi

	# Boot check where the binary can run on this host, with its own user folder.
	host_platform="linux"
	case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) host_platform="windows" ;; Darwin) host_platform="macos" ;; esac
	if [ "${SKIP_BOOT_TEST:-0}" != "1" ] && [ "$platform" = "$host_platform" ]; then
		boot_data="$OUT_DIR/.boot_userdata"
		mkdir -p "$boot_data"
		boot_log="$(APPDATA="$boot_data" XDG_DATA_HOME="$boot_data" "$binary" --headless --audio-driver Dummy --quit-after 300 -- offline 2>&1)" || {
			echo "$boot_log"; rm -rf "$boot_data"; echo "The exported binary did not boot cleanly." >&2; exit 1; }
		rm -rf "$boot_data"
		echo "$boot_log"
		# Here-string: with pipefail, "echo | grep -q" on a long log can fail with SIGPIPE.
		if grep -Eq "SCRIPT ERROR|Parse Error|Failed to load" <<< "$boot_log"; then
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
