"""Adds the store export presets to export_presets.cfg: "Android AAB" (Gradle build, Android App
Bundle for Google Play) and "iOS" (Xcode project). Idempotent: an existing preset of the same name is
updated in place, all other presets stay untouched.

Usage:  python3 tools/ci/store_presets.py [path/to/export_presets.cfg] [android-aab] [ios]
        (default: ./export_presets.cfg, both presets)

tools/export_build.sh runs it on export_presets.cfg for the "android-aab" and "ios" platforms and
restores the file afterwards, so the repository copy never changes (in CI the checkout is a
throwaway copy anyway). Once the orchestrator puts the same presets into the real file, this script
only refreshes the values below.

Environment (all optional):
  APPLE_TEAM_ID   App Store team ID (10 characters). Without it the Xcode project gets a
                  placeholder; set the team in Xcode (Signing & Capabilities) before building.
  BUILD_NUMBER    iOS CFBundleVersion (must grow with every TestFlight upload of one version);
                  tools/export_build.sh passes the same number as the Android versionCode.
Secrets never go into the presets: the Android keystore comes from GODOT_ANDROID_KEYSTORE_RELEASE_*,
the Apple certificates from the keychain of the build Mac (tools/ci/ios_build.sh).
"""
import os
import re
import sys
from pathlib import Path

# Android App Bundle for Google Play: same as the "Android" preset plus the Gradle build.
AAB_NAME = "Android AAB"
AAB_SOURCE = "Android"
AAB_SETTINGS = {
    "name": '"Android AAB"',
    "runnable": "false",
    "export_path": '"builds/android/Soulwick.aab"',
}
AAB_OPTIONS = {
    "gradle_build/use_gradle_build": "true",
    # 0 APK, 1 AAB
    "gradle_build/export_format": "1",
    # Godot 4.7.2 defaults, written out so a Godot update cannot change them silently.
    # Google Play: new apps and updates must target the API level of the last year (docs/STORES.md).
    "gradle_build/min_sdk": '"24"',
    "gradle_build/target_sdk": '"36"',
    # Play requires 64 bit; 32 bit ARM stays for older phones (as in the APK).
    "architectures/armeabi-v7a": "true",
    "architectures/arm64-v8a": "true",
    "architectures/x86": "false",
    "architectures/x86_64": "false",
    "package/signed": "true",
}

IOS_NAME = "iOS"
IOS_SETTINGS = {
    "name": '"iOS"',
    "platform": '"iOS"',
    "runnable": "false",
    "advanced_options": "false",
    "dedicated_server": "false",
    "custom_features": '""',
    "export_filter": '"all_resources"',
    "export_path": '"builds/ios/Soulwick.ipa"',
    "patches": "PackedStringArray()",
    "encryption_include_filters": '""',
    "encryption_exclude_filters": '""',
    "seed": "0",
    "encrypt_pck": "false",
    "encrypt_directory": "false",
    "script_export_mode": "2",
}
IOS_OPTIONS = {
    "custom_template/debug": '""',
    "custom_template/release": '""',
    "architectures/arm64": "true",
    "application/app_store_team_id": '"TEAMID0000"',
    # 0 App Store, 1 Development, 2 Ad-Hoc, 3 Enterprise
    "application/export_method_debug": "1",
    "application/export_method_release": "0",
    "application/bundle_identifier": '"com.webbude.soulwick"',
    "application/short_version": '""',
    "application/version": '""',
    # Godot writes only the Xcode project; tools/ci/ios_build.sh archives and signs it on a Mac.
    "application/export_project_only": "true",
    "application/delete_old_export_files_unconditionally": "true",
    # 0 iPhone, 1 iPad, 2 iPhone & iPad
    "application/targeted_device_family": "2",
    # Pixel art: nearest neighbour when Godot scales the icon.
    "application/icon_interpolation": "0",
    # Interim icon (opaque, the App Store refuses transparent icons) until the store icon exists
    # (docs/STORES.md, store graphics briefing).
    "icons/icon_1024x1024": '"res://deploy/web/icons/icon_512.png"',
    "storyboard/image_scale_mode": "0",
    "storyboard/use_custom_bg_color": "true",
    # #15131f, the background of menus and web page
    "storyboard/custom_bg_color": "Color(0.08235294, 0.07450981, 0.12156863, 1)",
    "entitlements/game_center": "false",
    "entitlements/push_notifications": '"Disabled"',
    "user_data/accessible_from_files_app": "false",
    "user_data/accessible_from_itunes_sharing": "false",
    "privacy/tracking_enabled": "false",
}

SECTION = re.compile(r"^\[preset\.(\d+)(\.options)?\]\s*$", re.M)


def sections(text):
    """[(index, is_options, start, end)] of every preset section, end = start of the next one."""
    found = list(SECTION.finditer(text))
    out = []
    for i, match in enumerate(found):
        end = found[i + 1].start() if i + 1 < len(found) else len(text)
        out.append((int(match.group(1)), bool(match.group(2)), match.start(), end))
    return out


def preset_index(text, name):
    for index, is_options, start, end in sections(text):
        if not is_options and re.search(r'^name="%s"\s*$' % re.escape(name), text[start:end], re.M):
            return index
    return None


def section_body(text, index, options):
    for i, is_options, start, end in sections(text):
        if i == index and is_options == options:
            return start, end
    raise SystemExit("[preset.%d%s] is missing." % (index, ".options" if options else ""))


def set_values(body, values):
    for key, value in values.items():
        line = "%s=%s" % (key, value)
        pattern = re.compile(r"^%s=.*$" % re.escape(key), re.M)
        if pattern.search(body):
            body = pattern.sub(lambda _m: line, body)
        else:
            body = body.rstrip("\n") + "\n" + line + "\n"
    return body.rstrip("\n") + "\n\n"


def replace_section(text, index, options, values):
    start, end = section_body(text, index, options)
    header_end = text.index("\n", start) + 1
    body = set_values(text[header_end:end], values)
    return text[:header_end] + body + text[end:]


def next_index(text):
    return max([i for i, _o, _s, _e in sections(text)] or [-1]) + 1


def append_preset(text, header_lines, option_lines):
    index = next_index(text)
    block = "[preset.%d]\n\n%s\n[preset.%d.options]\n\n%s" % (index, header_lines, index, option_lines)
    return text.rstrip("\n") + "\n\n" + block.rstrip("\n") + "\n", index


def ensure_aab(text):
    index = preset_index(text, AAB_NAME)
    if index is None:
        source = preset_index(text, AAB_SOURCE)
        if source is None:
            raise SystemExit('No export preset named "%s" to copy the AAB preset from.' % AAB_SOURCE)
        start, end = section_body(text, source, False)
        header = text[text.index("\n", start) + 1:end].strip("\n") + "\n"
        start, end = section_body(text, source, True)
        options = text[text.index("\n", start) + 1:end].strip("\n") + "\n"
        text, index = append_preset(text, header, options)
    text = replace_section(text, index, False, AAB_SETTINGS)
    return replace_section(text, index, True, AAB_OPTIONS)


def ensure_ios(text):
    settings = dict(IOS_SETTINGS)
    # Same file filters as the other presets (the Android preset is the reference).
    source = preset_index(text, AAB_SOURCE)
    if source is not None:
        start, end = section_body(text, source, False)
        body = text[start:end]
        for key in ("include_filter", "exclude_filter"):
            match = re.search(r"^%s=(.*)$" % key, body, re.M)
            if match:
                settings[key] = match.group(1)
    options = dict(IOS_OPTIONS)
    team = os.environ.get("APPLE_TEAM_ID", "").strip()
    if team:
        if not re.fullmatch(r"[A-Z0-9]{10}", team):
            raise SystemExit("APPLE_TEAM_ID must be 10 letters or digits (Apple Developer -> Membership).")
        options["application/app_store_team_id"] = '"%s"' % team
    build = os.environ.get("BUILD_NUMBER", "").strip()
    if build:
        if not re.fullmatch(r"[0-9]+", build):
            raise SystemExit("BUILD_NUMBER must be a whole number.")
        options["application/version"] = '"%s"' % build
    index = preset_index(text, IOS_NAME)
    if index is None:
        text, index = append_preset(text, "\n", "\n")
    text = replace_section(text, index, False, settings)
    return replace_section(text, index, True, options)


def main():
    args = sys.argv[1:]
    path = Path("export_presets.cfg")
    if args and args[0].endswith(".cfg"):
        path = Path(args.pop(0))
    wanted = args or ["android-aab", "ios"]
    original = path.read_text(encoding="utf-8")
    text = original
    for name in wanted:
        if name == "android-aab":
            text = ensure_aab(text)
        elif name == "ios":
            text = ensure_ios(text)
        else:
            raise SystemExit("Unknown preset '%s' (android-aab, ios)." % name)
    text = text.rstrip("\n") + "\n"
    if text != original:
        path.write_text(text, encoding="utf-8", newline="\n")
        print("%s: store presets set (%s)." % (path, ", ".join(wanted)))
    else:
        print("%s: store presets already up to date." % path)


if __name__ == "__main__":
    main()
