#!/usr/bin/env python3
"""Sammelt die Dev-Feedback-Notizen (F9 im Spiel, ui/dev/dev_feedback.gd) zu einer Uebersicht.

Aufruf (im Repo-Root):
    python tools/collect_feedback.py                         # alle Notizen -> docs/feedback/FEEDBACK_<heute>.md
    python tools/collect_feedback.py --since 2026-10-15      # nur Notizen ab diesem Tag (auch "2026-10-15 14:00")
    python tools/collect_feedback.py --group location        # nach Ort (Menue, Dorf, Biom) statt nach Kategorie
    python tools/collect_feedback.py --out C:/tmp/review.md  # andere Zieldatei (Bilder landen daneben in <datum>/)
    python tools/collect_feedback.py --src <ordner>          # anderer Quellordner (Standard siehe unten)
    python tools/collect_feedback.py --no-copy               # Bilder nicht kopieren, Links zeigen auf die Quelle

Quelle: %APPDATA%/Godot/app_userdata/Soulwick/dev_feedback/ (Linux ~/.local/share/godot/...,
macOS ~/Library/Application Support/Godot/...). Je Notiz ein Ordner <YYYY-MM-DD_HH-MM-SS>_<nr>/
mit screenshot.png, marked.png und note.json.
Ziel: die Markdown-Uebersicht (gruppiert nach Kategorie oder Ort, mit Text, Markierungen, den
UI- und Welt-Knoten unter jeder Markierung und dem Kontext) und eine Kopie von marked.png,
screenshot.png und note.json je Notiz unter docs/feedback/<datum>/<ordner>/; die Links in der
Uebersicht sind relativ. docs/feedback/ ist bis auf README.md gitignored (lokales Arbeitsmaterial).
Nur Python-Standardbibliothek.
"""
import argparse
import datetime as dt
import json
import os
import shutil
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CATEGORIES = ["UI", "Grafik", "Licht", "Raum/Layout", "Gameplay", "Bug", "Text"]
NO_CATEGORY = "Ohne Kategorie"
COPY_FILES = ["marked.png", "screenshot.png", "note.json"]
MAX_NODES_IN_REPORT = 6


def default_source() -> Path:
    if sys.platform.startswith("win"):
        base = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
        return base / "Godot" / "app_userdata" / "Soulwick" / "dev_feedback"
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "Godot" / "app_userdata" / "Soulwick" / "dev_feedback"
    base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
    return base / "godot" / "app_userdata" / "Soulwick" / "dev_feedback"


def parse_since(text: str) -> dt.datetime:
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%dT%H:%M", "%Y-%m-%d"):
        try:
            return dt.datetime.strptime(text, fmt)
        except ValueError:
            pass
    raise argparse.ArgumentTypeError(f"Datum nicht lesbar: {text!r} (erwartet YYYY-MM-DD oder 'YYYY-MM-DD HH:MM')")


def note_time(record: dict, folder: Path) -> dt.datetime:
    text = str(record.get("time", ""))
    try:
        return dt.datetime.fromisoformat(text.replace(" ", "T"))
    except ValueError:
        pass
    try:
        return dt.datetime.strptime(folder.name.rsplit("_", 1)[0], "%Y-%m-%d_%H-%M-%S")
    except ValueError:
        return dt.datetime.fromtimestamp(folder.stat().st_mtime)


def load_notes(source: Path, since: dt.datetime | None) -> list[dict]:
    notes = []
    if not source.is_dir():
        return notes
    for folder in sorted(p for p in source.iterdir() if p.is_dir()):
        note_file = folder / "note.json"
        if not note_file.is_file():
            continue
        try:
            record = json.loads(note_file.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            print(f"Uebersprungen (note.json kaputt): {folder.name}: {error}", file=sys.stderr)
            continue
        when = note_time(record, folder)
        if since is not None and when < since:
            continue
        record["_folder"] = folder
        record["_time"] = when
        notes.append(record)
    notes.sort(key=lambda r: (r["_time"], int(r.get("id", 0))))
    return notes


def ordered_categories(record: dict) -> list[str]:
    chosen = [str(c) for c in record.get("categories", [])]
    known = [c for c in CATEGORIES if c in chosen]
    return known + [c for c in chosen if c not in known]


def location_group(record: dict) -> str:
    context = record.get("context", {}) or {}
    phase = str(context.get("phase", ""))
    if phase == "dungeon":
        dungeon = context.get("dungeon", {}) or {}
        biome = dungeon.get("biome_name") or dungeon.get("biome") or "?"
        return f"Dungeon · {biome}"
    return {"menu": "Hauptmenü", "village": "Dorf"}.get(phase, str(context.get("scene_name", "") or "Unbekannt"))


def md_escape(text: str) -> str:
    return str(text).replace("|", "/").replace("\r", "")


def rel_link(target: Path, base: Path) -> str:
    try:
        return Path(os.path.relpath(target, base)).as_posix()
    except ValueError:  # other drive on Windows
        return target.resolve().as_uri()


def copy_note(record: dict, image_root: Path) -> Path:
    folder: Path = record["_folder"]
    target = image_root / folder.name
    target.mkdir(parents=True, exist_ok=True)
    for name in COPY_FILES:
        source = folder / name
        if source.is_file():
            shutil.copy2(source, target / name)
    return target


def describe_node(entry: dict) -> str:
    parts = [f"`{entry.get('path', '?')}`", str(entry.get("class", ""))]
    if entry.get("text"):
        parts.append(f'"{md_escape(entry["text"])}"')
    for key in ("texture", "tile_set", "script", "holder_script", "scene"):
        value = entry.get(key)
        if value:
            parts.append(f"{key}: `{value}`")
    tiles = entry.get("tiles")
    if tiles:
        parts.append("Kacheln: " + ", ".join(f"{t.get('tile')}×{t.get('cells')}" for t in tiles[:4]))
    return " · ".join(p for p in parts if p)


def context_lines(record: dict) -> list[str]:
    context = record.get("context", {}) or {}
    lines = []
    scene = context.get("scene")
    if scene:
        lines.append(f"Szene `{scene}`")
    dungeon = context.get("dungeon", {}) or {}
    if dungeon:
        bits = []
        for key, label in (("room_index", "Raum"), ("cycle", "Zyklus"), ("biome_name", "Biom"), ("room_type", "Art"),
                           ("room_kind", "Sorte"), ("room_size", "Größe"), ("special_type", "Spezial"), ("mode", "Modus"),
                           ("variant", "Variante"), ("kind_label", "Name"), ("seed", "Seed")):
            value = dungeon.get(key)
            if value not in (None, "", "<null>"):
                bits.append(f"{label} {value}")
        if bits:
            lines.append(", ".join(bits))
        if dungeon.get("template"):
            lines.append(f"Vorlage `{dungeon['template']}`")
    for player in context.get("players", []) or []:
        tile = player.get("room_tile") or player.get("tile")
        side = " (Seitenansicht)" if player.get("side_view") else ""
        lines.append(f"Spieler bei Kachel {tile} (Welt {player.get('position')}){side}")
    camera = context.get("camera", {}) or {}
    window = context.get("window", {}) or {}
    view = []
    if camera.get("zoom"):
        view.append(f"Zoom {camera['zoom']}")
    if window.get("window_size"):
        view.append(f"Fenster {window['window_size']}")
    if window.get("view_size"):
        view.append(f"Ansicht {window['view_size']}")
    if view:
        lines.append(", ".join(view))
    if context.get("pause_reasons"):
        lines.append("Offen: " + ", ".join(context["pause_reasons"]))
    version = record.get("version", {}) or {}
    if version.get("commit") or version.get("branch"):
        lines.append(f"Stand {version.get('branch', '?')} @ {version.get('commit', '?')}")
    return lines


def render_note(record: dict, link_dir: Path, base: Path) -> list[str]:
    number = record.get("id", "?")
    when = record["_time"].strftime("%Y-%m-%d %H:%M")
    location = md_escape(record.get("location", "")) or location_group(record)
    out = [f"### #{number} · {when} · {location}", ""]
    marked = link_dir / "marked.png"
    out.append(f"![#{number}]({rel_link(marked, base)})")
    out.append("")
    text = str(record.get("text", "")).strip()
    if text:
        out.extend("> " + line if line else ">" for line in text.splitlines())
        out.append("")
    categories = ordered_categories(record)
    out.append(f"- **Kategorien:** {', '.join(categories) if categories else '–'}")
    marks = record.get("marks", []) or []
    if marks:
        out.append("- **Markierungen:**")
        for mark in marks:
            px = mark.get("rect_px", {})
            rel = mark.get("rect_rel", {})
            note = md_escape(mark.get("note", "")).strip()
            head = f"  {mark.get('nr', '?')}. {note or '(ohne eigene Notiz)'}"
            head += f" – px {px.get('x')},{px.get('y')} {px.get('w')}×{px.get('h')}"
            head += f" (rel {rel.get('x')},{rel.get('y')} {rel.get('w')}×{rel.get('h')})"
            out.append(head)
            for entry in (mark.get("ui_nodes") or [])[:MAX_NODES_IN_REPORT]:
                out.append(f"     - UI: {describe_node(entry)}")
            for entry in (mark.get("world_nodes") or [])[:MAX_NODES_IN_REPORT]:
                out.append(f"     - Welt: {describe_node(entry)}")
    if record.get("strokes"):
        out.append(f"- **Striche:** {len(record['strokes'])}")
    lines = context_lines(record)
    if lines:
        out.append("- **Kontext:** " + " · ".join(md_escape(line) for line in lines))
    out.append(f"- **Dateien:** [screenshot.png]({rel_link(link_dir / 'screenshot.png', base)}) · "
               f"[note.json]({rel_link(link_dir / 'note.json', base)})")
    out.append("")
    return out


def build_report(notes: list[dict], group: str, links: dict, base: Path, source: Path, since: dt.datetime | None,
                 today: str) -> str:
    out = [f"# Dev-Feedback {today}", ""]
    since_text = f" seit {since:%Y-%m-%d %H:%M}" if since else ""
    out.append(f"{len(notes)} Notizen{since_text} aus `{source}`. Erzeugt mit `python tools/collect_feedback.py`; "
               "Anleitung: [README.md](README.md).")
    out.append("")
    if not notes:
        out.append("Keine Notizen gefunden.")
        return "\n".join(out) + "\n"

    by_category: dict[str, list[dict]] = {}
    for record in notes:
        for category in ordered_categories(record) or [NO_CATEGORY]:
            by_category.setdefault(category, []).append(record)
    by_location: dict[str, list[dict]] = {}
    for record in notes:
        by_location.setdefault(location_group(record), []).append(record)

    out += ["## Übersicht", "", "| Kategorie | Notizen |", "| --- | --- |"]
    for category in CATEGORIES + sorted(set(by_category) - set(CATEGORIES)):
        if category in by_category:
            out.append(f"| {category} | {len(by_category[category])} |")
    out += ["", "| Ort | Notizen |", "| --- | --- |"]
    for location in sorted(by_location):
        out.append(f"| {md_escape(location)} | {len(by_location[location])} |")
    out.append("")

    if group == "location":
        for location in sorted(by_location):
            out += [f"## {md_escape(location)} ({len(by_location[location])})", ""]
            for record in by_location[location]:
                out += render_note(record, links[id(record)], base)
    else:
        order = [c for c in CATEGORIES if c in by_category] + sorted(set(by_category) - set(CATEGORIES))
        for category in order:
            records = by_category[category]
            out += [f"## {category} ({len(records)})", ""]
            refs = []
            for record in records:
                primary = (ordered_categories(record) or [NO_CATEGORY])[0]
                if primary == category:
                    out += render_note(record, links[id(record)], base)
                else:
                    refs.append(f"#{record.get('id', '?')} (siehe {primary})")
            if refs:
                out += ["Auch hier: " + ", ".join(refs), ""]
    return "\n".join(out) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Dev-Feedback-Notizen (F9) zu einer Markdown-Uebersicht sammeln.")
    parser.add_argument("--src", type=Path, default=default_source(), help="Quellordner (Standard: user://dev_feedback)")
    parser.add_argument("--since", type=parse_since, default=None, help="nur Notizen ab Datum (YYYY-MM-DD [HH:MM])")
    parser.add_argument("--out", type=Path, default=None, help="Zieldatei (Standard: docs/feedback/FEEDBACK_<heute>.md)")
    parser.add_argument("--group", choices=["category", "location"], default="category", help="Gruppierung")
    parser.add_argument("--no-copy", action="store_true", help="Bilder nicht kopieren, auf die Quelle verlinken")
    args = parser.parse_args()

    today = dt.date.today().isoformat()
    out_file: Path = args.out or (REPO_ROOT / "docs" / "feedback" / f"FEEDBACK_{today}.md")
    out_file = out_file.resolve()
    out_file.parent.mkdir(parents=True, exist_ok=True)
    image_root = out_file.parent / today

    notes = load_notes(args.src, args.since)
    links = {}
    for record in notes:
        links[id(record)] = record["_folder"] if args.no_copy else copy_note(record, image_root)
    report = build_report(notes, args.group, links, out_file.parent, args.src, args.since, today)
    out_file.write_text(report, encoding="utf-8", newline="\n")
    copied = "" if args.no_copy or not notes else f", Bilder in {image_root}"
    print(f"{len(notes)} Notizen -> {out_file}{copied}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
