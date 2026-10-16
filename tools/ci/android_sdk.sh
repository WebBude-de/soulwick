#!/usr/bin/env bash
# Installs the Android SDK packages the Godot 4.7 APK export needs (release.yml; same as the build
# PC, docs/MULTIPLAYER.md §3d): platform-tools, build-tools 35.0.1 and 36.1.0, platforms 35 and 36.
# No NDK, CMake or Gradle (the "Android" preset has use_gradle_build=false).
#
# Uses the SDK in $ANDROID_HOME when it has the command-line tools (GitHub's Ubuntu runners have
# one preinstalled), otherwise downloads the command-line tools into $RUNNER_TEMP/android-sdk.
# Writes ANDROID_HOME and ANDROID_BUILD_TOOLS to $GITHUB_ENV when set. Godot takes ANDROID_HOME and
# JAVA_HOME as its Android SDK and JDK paths, so run this (and set up JDK 17) before Godot starts.
set -euo pipefail

CMDLINE_TOOLS_URL="${CMDLINE_TOOLS_URL:-https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip}"
BUILD_TOOLS="36.1.0"
PACKAGES=("platform-tools" "build-tools;35.0.1" "build-tools;$BUILD_TOOLS" "platforms;android-35" "platforms;android-36")

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
sdkmanager="$sdk/cmdline-tools/latest/bin/sdkmanager"
if [ -z "$sdk" ] || [ ! -x "$sdkmanager" ]; then
	sdk="${RUNNER_TEMP:-/tmp}/android-sdk"
	sdkmanager="$sdk/cmdline-tools/latest/bin/sdkmanager"
	echo "No Android SDK with command-line tools found; installing into $sdk"
	mkdir -p "$sdk/cmdline-tools"
	archive="$(mktemp --suffix=.zip)"
	curl -fsSL --retry 3 -o "$archive" "$CMDLINE_TOOLS_URL"
	unzip -q -o "$archive" -d "$sdk/cmdline-tools"
	rm -rf "$sdk/cmdline-tools/latest"
	mv "$sdk/cmdline-tools/cmdline-tools" "$sdk/cmdline-tools/latest"
	rm -f "$archive"
fi

# sdkmanager exits non-zero when "yes" stops early; the install below fails if licenses are missing.
yes | "$sdkmanager" --sdk_root="$sdk" --licenses >/dev/null 2>&1 || true
"$sdkmanager" --sdk_root="$sdk" --install "${PACKAGES[@]}" >/dev/null
for tool in "platform-tools/adb" "build-tools/$BUILD_TOOLS/apksigner" "build-tools/$BUILD_TOOLS/aapt"; do
	if [ ! -x "$sdk/$tool" ]; then
		echo "::error::Android SDK: $sdk/$tool is missing after sdkmanager." >&2
		exit 1
	fi
done
echo "Android SDK ready: $sdk (${PACKAGES[*]})"

if [ -n "${GITHUB_ENV:-}" ]; then
	{
		echo "ANDROID_HOME=$sdk"
		echo "ANDROID_SDK_ROOT=$sdk"
		echo "ANDROID_BUILD_TOOLS=$sdk/build-tools/$BUILD_TOOLS"
	} >> "$GITHUB_ENV"
fi
