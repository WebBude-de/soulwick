"""Adjusts the service worker that Godot writes for the "Web" export (index.service.worker.js).

Usage:  python3 deploy/web/patch_service_worker.py <export folder>   (the Dockerfile runs it on /out)

Godot's worker caches the game under the file names (index.html, index.pck …). Two gaps for us:

1. Navigation to the folder ("/", "/?install", the link of the website) never matches the cached
   "index.html": offline, the browser shows its own error page instead of the game. The patch looks
   up "index.html" for such navigations and ignores the query string (`?install`).
2. Font and icons of the start page are not cached: offline the page falls back to a plain font.
   The patch adds the files that exist in the export folder to the files cached on install (a
   missing file would make the whole install fail, so only existing files are added).

Every change checks its anchor in Godot's code and fails loudly if Godot changed it, so a new Godot
version cannot silently ship an unpatched worker. Idempotent: a patched worker stays as it is.
"""
import json
import re
import sys
from pathlib import Path

WORKER = "index.service.worker.js"
MARKER = "/* soulwick: patched by deploy/web/patch_service_worker.py */"
# Start page extras: font (copied by the Dockerfile) and the icons the page and manifest link.
EXTRA_FILES = [
    "index.manifest.json",
    "fonts/PixelifySans-Variable.ttf",
    "index.144x144.png",
    "index.180x180.png",
    "index.512x512.png",
]

CACHED_FILES_RE = re.compile(r"^const CACHED_FILES = (\[.*\]);$", re.M)
MATCH_ANCHOR = "let cached = await cache.match(event.request);"
MATCH_PATCH = (
    "// soulwick: the folder (\"/\", \"/?install\") is the game page too; ignore the query.\n"
    "\t\t\t\tlet cached = await cache.match(event.request, isNavigate ? { ignoreSearch: true } : undefined);\n"
    "\t\t\t\tif (cached == null && isNavigate && new URL(event.request.url).pathname.endsWith('/')) {\n"
    "\t\t\t\t\tcached = await cache.match(CACHED_FILES[0]);\n"
    "\t\t\t\t}"
)


def patch(text: str, export_dir: Path) -> str:
    if MARKER in text:
        return text
    match = CACHED_FILES_RE.search(text)
    if not match:
        raise SystemExit("%s: 'const CACHED_FILES = [...]' not found (Godot changed the worker?)." % WORKER)
    cached = json.loads(match.group(1))
    if not cached or cached[0] != "index.html":
        raise SystemExit("%s: CACHED_FILES[0] is not index.html: %s" % (WORKER, cached))
    for name in EXTRA_FILES:
        if (export_dir / name).is_file() and name not in cached:
            cached.append(name)
    text = text[: match.start(1)] + json.dumps(cached) + text[match.end(1):]
    if text.count(MATCH_ANCHOR) != 1:
        raise SystemExit("%s: anchor %r not found exactly once (Godot changed the worker?)." % (WORKER, MATCH_ANCHOR))
    text = text.replace(MATCH_ANCHOR, MATCH_PATCH)
    return MARKER + "\n" + text


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    export_dir = Path(sys.argv[1])
    worker = export_dir / WORKER
    original = worker.read_text(encoding="utf-8")
    updated = patch(original, export_dir)
    if updated == original:
        print("%s: already patched." % worker)
        return
    worker.write_text(updated, encoding="utf-8", newline="\n")
    cached = json.loads(CACHED_FILES_RE.search(updated).group(1))
    print("%s: patched (folder navigation, cached on install: %s)." % (worker, ", ".join(cached)))


if __name__ == "__main__":
    main()
