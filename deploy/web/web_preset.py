"""Sets the options of the "Web" export preset that the browser build needs (custom page, app icons,
offline page, installable app). Idempotent: options that already have these values stay as they are.

Usage:  python3 deploy/web/web_preset.py [path/to/export_presets.cfg]   (default: ./export_presets.cfg)

The Dockerfile runs it on its own copy of the project, so the image never depends on the state of
the preset in the repository. The same values belong into the real preset (docs/WEB_BUILD.md §3);
once they are there this script changes nothing.
"""
import re
import sys
from pathlib import Path

PRESET_NAME = "Web"
OPTIONS = {
    # Godot's default favicon is the engine logo: the page links the app icons itself.
    "html/export_icon": "false",
    "html/custom_html_shell": '"res://deploy/web/shell.html"',
    "progressive_web_app/enabled": "true",
    "progressive_web_app/ensure_cross_origin_isolation_headers": "true",
    "progressive_web_app/offline_page": '"res://deploy/web/offline.html"',
    # 0 fullscreen, 1 standalone, 2 minimal UI, 3 browser
    "progressive_web_app/display": "1",
    # 0 any, 1 landscape, 2 portrait
    "progressive_web_app/orientation": "1",
    "progressive_web_app/icon_144x144": '"res://deploy/web/icons/icon_144.png"',
    "progressive_web_app/icon_180x180": '"res://deploy/web/icons/icon_180.png"',
    "progressive_web_app/icon_512x512": '"res://deploy/web/icons/icon_512.png"',
    # #15131f, the page background
    "progressive_web_app/background_color": "Color(0.08235294, 0.07450981, 0.12156863, 1)",
}


def apply(text: str) -> str:
    match = re.search(r'^\[preset\.(\d+)\]\s*\n(?:(?!^\[).*\n)*?^name="%s"' % re.escape(PRESET_NAME), text, re.M)
    if not match:
        raise SystemExit('No export preset named "%s".' % PRESET_NAME)
    header = "[preset.%s.options]" % match.group(1)
    start = text.find(header)
    if start < 0:
        raise SystemExit("%s is missing." % header)
    body_start = start + len(header)
    next_section = re.search(r"^\[", text[body_start:], re.M)
    body_end = body_start + next_section.start() if next_section else len(text)
    body = text[body_start:body_end]
    for key, value in OPTIONS.items():
        line = "%s=%s" % (key, value)
        pattern = re.compile(r"^%s=.*$" % re.escape(key), re.M)
        if pattern.search(body):
            body = pattern.sub(lambda _m: line, body)
        else:
            body = body.rstrip("\n") + "\n" + line + "\n"
    if next_section and not body.endswith("\n\n"):
        body = body.rstrip("\n") + "\n\n"
    return text[:body_start] + body + text[body_end:]


def main():
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "export_presets.cfg")
    original = path.read_text(encoding="utf-8")
    updated = apply(original)
    if updated != original:
        path.write_text(updated, encoding="utf-8", newline="\n")
        print("%s: Web preset updated." % path)
    else:
        print("%s: Web preset already up to date." % path)


if __name__ == "__main__":
    main()
