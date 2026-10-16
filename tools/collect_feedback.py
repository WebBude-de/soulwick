#!/usr/bin/env python3
"""Sammelt die Fehlermeldungen (Taste # oder F9 im Spiel, ui/dev/dev_feedback.gd) zu einer Uebersicht.

Aufruf (im Repo-Root):
    python tools/collect_feedback.py                         # lokale Meldungen -> docs/feedback/FEEDBACK_<heute>.md
    python tools/collect_feedback.py --since 2026-10-15      # nur Meldungen ab diesem Tag (auch "2026-10-15 14:00")
    python tools/collect_feedback.py --group location        # nach Ort (Menue, Dorf, Biom) statt nach Kategorie
    python tools/collect_feedback.py --out C:/tmp/review.md  # andere Zieldatei (Bilder landen daneben in <datum>/)
    python tools/collect_feedback.py --src <ordner>          # anderer Quellordner (Standard siehe unten)
    python tools/collect_feedback.py --no-copy               # Bilder nicht kopieren, Links zeigen auf die Quelle

Meldungen aller Spieler vom Server (Admin-Login wie das Admin-Panel, nur ueber die API):
    set SOULWICK_ADMIN_EMAIL=...  /  set SOULWICK_ADMIN_PASSWORD=...
    python tools/collect_feedback.py --api https://api-dev.playsoulwick.com            # Status "new"
    python tools/collect_feedback.py --api http://localhost:8787 --status all --limit 200
    python tools/collect_feedback.py --api ... --mark-seen   # danach auf "seen" setzen (PATCH)

Quelle lokal: %APPDATA%/Godot/app_userdata/Soulwick/dev_feedback/ (Linux ~/.local/share/godot/...,
macOS ~/Library/Application Support/Godot/...). Je Meldung ein Ordner <YYYY-MM-DD_HH-MM-SS>_<nr>/
mit screenshot.png, marked.png, note.json und (nach dem Upload) upload.json.
Quelle Server: GET /admin/bug-reports (Liste), /admin/bug-reports/:id (Details) und
/admin/bug-reports/:id/image (Bild), Vertrag soulwick-platform/packages/contracts/src/bug-report.ts.
Die Markierungen werden lokal ins Bild gezeichnet (marked.png, mit Pillow; ohne Pillow nur das
Originalbild und die Liste der Markierungen).
Ziel: die Markdown-Uebersicht (gruppiert nach Kategorie oder Ort, mit Text, Markierungen, den
UI- und Welt-Knoten unter jeder Markierung, dem Kontext und einer Spalte "pruefen?", die der
auswertende Agent setzt) und eine Kopie der Dateien je Meldung unter docs/feedback/<datum>/<ordner>/;
die Links in der Uebersicht sind relativ. docs/feedback/ ist bis auf README.md gitignored.
Nur Python-Standardbibliothek (Pillow optional).
"""
import argparse
import datetime as dt
import json
import os
import shutil
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
# Category keys of the game and the API (contract BugReportCategory) -> heading in the report.
CATEGORY_LABELS = {
    "ui": "UI", "graphics": "Grafik", "light": "Licht", "layout": "Raum/Layout",
    "gameplay": "Gameplay", "bug": "Bug", "text": "Text",
}
CATEGORIES = list(CATEGORY_LABELS.values())
NO_CATEGORY = "Ohne Kategorie"
COPY_FILES = ["marked.png", "screenshot.png", "note.json", "upload.json"]
MAX_NODES_IN_REPORT = 6
HTTP_TIMEOUT = 20
IMAGE_EXT = {"image/webp": "webp", "image/jpeg": "jpg", "image/png": "png"}
MARK_COLOR = (255, 41, 31, 255)
MARK_FILL = (255, 41, 31, 46)
STROKE_COLOR = (255, 217, 51, 255)


class ApiError(Exception):
    """A failed admin API call with a readable German hint."""


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
        upload = folder / "upload.json"
        if upload.is_file():
            try:
                record["_upload"] = json.loads(upload.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                pass
        record["_folder"] = folder
        record["_time"] = when
        notes.append(record)
    notes.sort(key=lambda r: (r["_time"], str(r.get("id", 0))))
    return notes


# --- server (admin API) -------------------------------------------------------------------------

def api_request(base: str, path: str, token: str = "", method: str = "GET", body: dict | None = None,
                raw: bool = False):
    url = base.rstrip("/") + path
    data = None
    headers = {"Accept": "application/json"}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
            payload = response.read()
            if raw:
                return payload, response.headers.get("Content-Type", "")
            return json.loads(payload.decode("utf-8")) if payload else None
    except urllib.error.HTTPError as error:
        code = f"http_{error.code}"
        try:
            parsed = json.loads(error.read().decode("utf-8"))
            code = parsed.get("error", code)
        except (ValueError, AttributeError, OSError):
            pass
        if error.code == 404 and path.startswith("/admin/bug-reports") and code in ("not_found", "http_404"):
            raise ApiError(f"Die Admin-Routen fuer Meldungen gibt es auf {base} noch nicht (404 bei {path}). "
                           "Nichts geholt; spaeter erneut versuchen.") from None
        if error.code == 401:
            raise ApiError(f"Anmeldung abgelehnt ({code}). SOULWICK_ADMIN_EMAIL/SOULWICK_ADMIN_PASSWORD pruefen.") from None
        if error.code == 403:
            raise ApiError(f"Keine Rechte fuer {path} ({code}); das Konto braucht die Rolle moderator oder admin.") from None
        if error.code == 429:
            raise ApiError("Zu viele Anfragen (rate_limited); kurz warten und erneut versuchen.") from None
        raise ApiError(f"{method} {path}: HTTP {error.code} ({code})") from None
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        raise ApiError(f"API {base} nicht erreichbar: {getattr(error, 'reason', error)}") from None
    except json.JSONDecodeError:
        raise ApiError(f"{method} {path}: Antwort ist kein JSON") from None


def admin_login(base: str) -> str:
    email = os.environ.get("SOULWICK_ADMIN_EMAIL", "").strip()
    password = os.environ.get("SOULWICK_ADMIN_PASSWORD", "")
    if not email or not password:
        raise ApiError("SOULWICK_ADMIN_EMAIL und SOULWICK_ADMIN_PASSWORD sind nicht gesetzt (Admin-Konto der Plattform).")
    answer = api_request(base, "/admin/auth/login", method="POST", body={"email": email, "password": password})
    token = (answer or {}).get("token", "")
    if not token:
        raise ApiError("Login ohne Token in der Antwort.")
    return token


def admin_logout(base: str, token: str) -> None:
    try:
        api_request(base, "/admin/auth/logout", token=token, method="POST")
    except ApiError:
        pass


def fetch_reports(base: str, token: str, status: str, limit: int, since: dt.datetime | None) -> list[dict]:
    items: list[dict] = []
    cursor = None
    while len(items) < limit:
        query = {"limit": str(min(100, limit - len(items)))}
        if status != "all":
            query["status"] = status
        if cursor:
            query["cursor"] = cursor
        page = api_request(base, "/admin/bug-reports?" + urllib.parse.urlencode(query), token=token) or {}
        page_items = page.get("items", []) or []
        stop = False
        for item in page_items:
            if since is not None and parse_api_time(item.get("createdAt")) < since:
                stop = True  # newest first: everything after is older
                break
            items.append(item)
        cursor = page.get("nextCursor")
        if stop or not cursor or not page_items:
            break
    return items


def parse_api_time(text) -> dt.datetime:
    try:
        value = dt.datetime.fromisoformat(str(text).replace("Z", "+00:00"))
        return value.astimezone().replace(tzinfo=None)
    except ValueError:
        return dt.datetime.min


def load_api_notes(base: str, status: str, limit: int, since: dt.datetime | None, image_root: Path,
                   mark_seen: bool) -> list[dict]:
    token = admin_login(base)
    notes = []
    try:
        for item in fetch_reports(base, token, status, limit, since):
            report_id = str(item.get("id", ""))
            try:
                detail = api_request(base, f"/admin/bug-reports/{urllib.parse.quote(report_id)}", token=token) or {}
            except ApiError as error:
                print(f"Meldung {report_id} uebersprungen: {error}", file=sys.stderr)
                continue
            when = parse_api_time(detail.get("createdAt", item.get("createdAt")))
            folder = image_root / f"{when:%Y-%m-%d_%H-%M-%S}_api-{report_id[:8]}"
            folder.mkdir(parents=True, exist_ok=True)
            image_path = None
            image_url = detail.get("imageUrl") or f"/admin/bug-reports/{report_id}/image"
            try:
                data, mime = api_request(base, image_url, token=token, raw=True)
                ext = IMAGE_EXT.get(str(detail.get("imageMime") or mime).split(";")[0].strip(), "img")
                image_path = folder / f"screenshot.{ext}"
                image_path.write_bytes(data)
            except ApiError as error:
                print(f"Bild von {report_id} nicht geholt: {error}", file=sys.stderr)
            record = api_record(detail, item, when, image_path)
            (folder / "note.json").write_text(json.dumps(detail, ensure_ascii=False, indent="\t"), encoding="utf-8")
            if image_path is not None:
                draw_marked(image_path, record, folder / "marked.png")
            record["_folder"] = folder
            notes.append(record)
            if mark_seen and detail.get("status") == "new":
                try:
                    api_request(base, f"/admin/bug-reports/{urllib.parse.quote(report_id)}", token=token,
                                method="PATCH", body={"status": "seen"})
                except ApiError as error:
                    print(f"Status von {report_id} nicht gesetzt: {error}", file=sys.stderr)
    finally:
        admin_logout(base, token)
    notes.sort(key=lambda r: r["_time"])
    return notes


def image_size(path: Path | None, context: dict) -> tuple[int, int] | None:
    if path is not None:
        try:
            from PIL import Image  # optional
            with Image.open(path) as image:
                return image.size
        except Exception:  # noqa: BLE001 - Pillow missing or image unreadable
            pass
    size = context.get("image_size")
    if isinstance(size, list) and len(size) >= 2:
        return int(size[0]), int(size[1])
    return None


def api_record(detail: dict, item: dict, when: dt.datetime, image_path: Path | None) -> dict:
    """An admin API report in the shape of a local note.json (so the report code is the same)."""
    context = detail.get("context") or {}
    size = image_size(image_path, context)
    nodes_by_nr = {int(entry.get("nr", 0)): entry for entry in (context.get("mark_nodes") or []) if isinstance(entry, dict)}
    marks = []
    for index, mark in enumerate(detail.get("marks") or [], start=1):
        rel = {key: mark.get(key, 0) for key in ("x", "y", "w", "h")}
        entry = {"nr": index, "note": mark.get("note", ""), "rect_rel": rel}
        if size:
            entry["rect_px"] = {"x": round(rel["x"] * size[0]), "y": round(rel["y"] * size[1]),
                                "w": round(rel["w"] * size[0]), "h": round(rel["h"] * size[1])}
        nodes = nodes_by_nr.get(index, {})
        entry["ui_nodes"] = nodes.get("ui_nodes", [])
        entry["world_nodes"] = nodes.get("world_nodes", [])
        marks.append(entry)
    return {
        "id": str(detail.get("id", item.get("id", "")))[:8],
        "time": when.isoformat(sep=" "),
        "text": detail.get("note", ""),
        "categories": detail.get("categories") or item.get("categories") or [],
        "location": detail.get("location") or context.get("location", ""),
        "marks": marks,
        "strokes": detail.get("strokes") or [],
        "context": context,
        "version": context.get("version") or {"game": detail.get("gameVersion", "")},
        "_time": when,
        "_server": {
            "id": detail.get("id"), "status": detail.get("status"), "player": detail.get("playerName"),
            "platform": detail.get("platform"), "gameVersion": detail.get("gameVersion"),
            "image": image_path.name if image_path else None,
        },
    }


def draw_marked(image_path: Path, record: dict, target: Path) -> bool:
    """marked.png with the numbered rectangles and strokes (Pillow); False without Pillow."""
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        return False
    try:
        with Image.open(image_path) as source:
            base = source.convert("RGBA")
    except Exception:  # noqa: BLE001 - unreadable image
        return False
    width, height = base.size
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    line = max(2, round(height / 360))
    try:
        font = ImageFont.load_default(size=max(14, round(height / 36)))
    except TypeError:  # Pillow < 10.1
        font = ImageFont.load_default()
    for stroke in record.get("strokes") or []:
        points = stroke if isinstance(stroke, list) else stroke.get("points_px", [])
        pixels = [(float(p[0]) * width, float(p[1]) * height) if isinstance(stroke, list) else (p[0], p[1]) for p in points]
        if len(pixels) >= 2:
            draw.line(pixels, fill=STROKE_COLOR, width=line)
    for mark in record.get("marks") or []:
        rel = mark.get("rect_rel", {})
        box = [rel.get("x", 0) * width, rel.get("y", 0) * height,
               (rel.get("x", 0) + rel.get("w", 0)) * width, (rel.get("y", 0) + rel.get("h", 0)) * height]
        draw.rectangle(box, fill=MARK_FILL, outline=MARK_COLOR, width=line)
        label = str(mark.get("nr", "?"))
        text_box = draw.textbbox((box[0] + 4, box[1] + 2), label, font=font)
        draw.rectangle([box[0], box[1], text_box[2] + 4, text_box[3] + 3], fill=MARK_COLOR)
        draw.text((box[0] + 4, box[1] + 2), label, fill=(255, 255, 255, 255), font=font)
    Image.alpha_composite(base, layer).convert("RGB").save(target)
    return True


# --- report --------------------------------------------------------------------------------------

def category_label(category) -> str:
    return CATEGORY_LABELS.get(str(category), str(category))


def ordered_categories(record: dict) -> list[str]:
    chosen = [category_label(c) for c in record.get("categories", [])]
    known = [c for c in CATEGORIES if c in chosen]
    return known + [c for c in dict.fromkeys(chosen) if c not in known]


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


def one_line(text: str, length: int = 70) -> str:
    text = md_escape(" ".join(str(text).split()))
    return text if len(text) <= length else text[: length - 1] + "…"


def rel_link(target: Path, base: Path) -> str:
    try:
        return Path(os.path.relpath(target, base)).as_posix()
    except ValueError:  # other drive on Windows
        return target.resolve().as_uri()


def copy_note(record: dict, image_root: Path) -> Path:
    folder: Path = record["_folder"]
    target = image_root / folder.name
    if target.resolve() == folder.resolve():
        return target
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
        if not isinstance(player, dict):
            continue
        tile = player.get("room_tile") or player.get("tile")
        side = " (Seitenansicht)" if player.get("side_view") else ""
        lines.append(f"Spieler bei Kachel {tile} (Welt {player.get('position')}){side}")
    camera = context.get("camera", {}) or {}
    window = context.get("window", {}) or {}
    view = []
    if isinstance(camera, dict) and camera.get("zoom"):
        view.append(f"Zoom {camera['zoom']}")
    if isinstance(window, dict) and window.get("window_size"):
        view.append(f"Fenster {window['window_size']}")
    elif context.get("resolution"):
        view.append(f"Auflösung {context['resolution']}")
    if isinstance(window, dict) and window.get("view_size"):
        view.append(f"Ansicht {window['view_size']}")
    if context.get("locale"):
        view.append(f"Sprache {context['locale']}")
    if view:
        lines.append(", ".join(view))
    if context.get("pause_reasons"):
        lines.append("Offen: " + ", ".join(str(r) for r in context["pause_reasons"]))
    if context.get("truncated"):
        lines.append("Gekürzt (Kontext > 16 KiB): " + ", ".join(str(k) for k in context["truncated"]))
    version = record.get("version", {}) or {}
    if version.get("commit") or version.get("branch"):
        lines.append(f"Stand {version.get('branch', '?')} @ {version.get('commit', '?')}")
    return lines


def source_text(record: dict) -> str:
    server = record.get("_server")
    if server:
        bits = [f"Server {server.get('status', '?')}", str(server.get("platform") or "?"), f"v{server.get('gameVersion') or '?'}"]
        if server.get("player"):
            bits.append(f"Spieler {server['player']}")
        return " · ".join(bits)
    upload = record.get("_upload") or {}
    if upload.get("status") == "sent":
        return f"lokal · gesendet ({str(upload.get('id', ''))[:8]})"
    if upload.get("status") == "rejected":
        return f"lokal · abgelehnt ({upload.get('error', '?')} {upload.get('http_status', '')})".strip()
    return "lokal · nicht gesendet"


def image_names(record: dict, link_dir: Path) -> tuple[Path, Path]:
    marked = link_dir / "marked.png"
    server = record.get("_server") or {}
    original = link_dir / (server.get("image") or "screenshot.png")
    return (marked if marked.is_file() or not server else original), original


def render_note(record: dict, link_dir: Path, base: Path) -> list[str]:
    number = record.get("id", "?")
    when = record["_time"].strftime("%Y-%m-%d %H:%M")
    location = md_escape(record.get("location", "")) or location_group(record)
    out = [f"### #{number} · {when} · {location}", ""]
    shown, original = image_names(record, link_dir)
    out.append(f"![#{number}]({rel_link(shown, base)})")
    out.append("")
    text = str(record.get("text", "")).strip()
    if text:
        out.extend("> " + line if line else ">" for line in text.splitlines())
        out.append("")
    categories = ordered_categories(record)
    out.append(f"- **Kategorien:** {', '.join(categories) if categories else '–'}")
    out.append(f"- **Quelle:** {source_text(record)}")
    out.append("- **prüfen?** _(setzt der auswertende Agent: leer = plausibel, sonst `ja: Grund`; "
               "siehe README „Meldungen auswerten“)_")
    marks = record.get("marks", []) or []
    if marks:
        out.append("- **Markierungen:**")
        for mark in marks:
            px = mark.get("rect_px", {}) or {}
            rel = mark.get("rect_rel", {}) or {}
            note = md_escape(mark.get("note", "")).strip()
            head = f"  {mark.get('nr', '?')}. {note or '(ohne eigene Notiz)'}"
            if px:
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
    out.append(f"- **Dateien:** [{original.name}]({rel_link(original, base)}) · "
               f"[note.json]({rel_link(link_dir / 'note.json', base)})")
    out.append("")
    return out


def build_report(notes: list[dict], group: str, links: dict, base: Path, source: str, since: dt.datetime | None,
                 today: str) -> str:
    out = [f"# Dev-Feedback {today}", ""]
    since_text = f" seit {since:%Y-%m-%d %H:%M}" if since else ""
    out.append(f"{len(notes)} Meldungen{since_text} aus {source}. Erzeugt mit `python tools/collect_feedback.py`; "
               "Anleitung und Regeln fürs Auswerten: [README.md](README.md).")
    out.append("")
    if not notes:
        out.append("Keine Meldungen gefunden.")
        return "\n".join(out) + "\n"

    by_category: dict[str, list[dict]] = {}
    for record in notes:
        for category in ordered_categories(record) or [NO_CATEGORY]:
            by_category.setdefault(category, []).append(record)
    by_location: dict[str, list[dict]] = {}
    for record in notes:
        by_location.setdefault(location_group(record), []).append(record)

    out += ["## Übersicht", "", "| Kategorie | Meldungen |", "| --- | --- |"]
    for category in CATEGORIES + sorted(set(by_category) - set(CATEGORIES)):
        if category in by_category:
            out.append(f"| {category} | {len(by_category[category])} |")
    out += ["", "| Ort | Meldungen |", "| --- | --- |"]
    for location in sorted(by_location):
        out.append(f"| {md_escape(location)} | {len(by_location[location])} |")
    out += ["", "## Alle Meldungen", "",
            "Spalte **prüfen?** setzt der auswertende Agent: leer = plausibel, umsetzen; `ja: Grund` = unplausibel oder "
            "offensichtlich falsch, dem Projektmitglied zeigen (Bild, Notiz, Begründung), nicht still umsetzen oder verwerfen.",
            "", "| Nr | Zeit | Kategorien | Ort | Text | Quelle | prüfen? |", "| --- | --- | --- | --- | --- | --- | --- |"]
    for record in notes:
        text = str(record.get("text", "")).strip()
        if not text:
            text = next((str(m.get("note", "")) for m in record.get("marks", []) or [] if m.get("note")), "")
        out.append(f"| #{record.get('id', '?')} | {record['_time']:%Y-%m-%d %H:%M} | {', '.join(ordered_categories(record)) or '–'} | "
                   f"{one_line(record.get('location', '') or location_group(record), 40)} | {one_line(text)} | "
                   f"{md_escape(source_text(record))} |  |")
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
    parser = argparse.ArgumentParser(description="Fehlermeldungen (# / F9) zu einer Markdown-Uebersicht sammeln.")
    parser.add_argument("--src", type=Path, default=default_source(), help="lokaler Quellordner (Standard: user://dev_feedback)")
    parser.add_argument("--api", default=None, help="Basis-URL der Plattform-API: Meldungen aller Spieler vom Server holen")
    parser.add_argument("--status", default="new", choices=["new", "seen", "done", "wont_fix", "all"],
                        help="nur mit --api: Status der Meldungen (Standard new)")
    parser.add_argument("--limit", type=int, default=100, help="nur mit --api: hoechstens so viele Meldungen")
    parser.add_argument("--mark-seen", action="store_true", help="nur mit --api: geholte neue Meldungen auf seen setzen")
    parser.add_argument("--since", type=parse_since, default=None, help="nur Meldungen ab Datum (YYYY-MM-DD [HH:MM])")
    parser.add_argument("--out", type=Path, default=None, help="Zieldatei (Standard: docs/feedback/FEEDBACK_<heute>.md)")
    parser.add_argument("--group", choices=["category", "location"], default="category", help="Gruppierung")
    parser.add_argument("--no-copy", action="store_true", help="lokal: Bilder nicht kopieren, auf die Quelle verlinken")
    args = parser.parse_args()

    today = dt.date.today().isoformat()
    out_file: Path = args.out or (REPO_ROOT / "docs" / "feedback" / f"FEEDBACK_{today}.md")
    out_file = out_file.resolve()
    out_file.parent.mkdir(parents=True, exist_ok=True)
    image_root = out_file.parent / today

    links = {}
    if args.api:
        try:
            notes = load_api_notes(args.api, args.status, max(1, args.limit), args.since, image_root, args.mark_seen)
        except ApiError as error:
            print(f"Keine Meldungen vom Server: {error}", file=sys.stderr)
            return 2
        for record in notes:
            links[id(record)] = record["_folder"]
        source = f"`{args.api}` (Status {args.status})"
    else:
        notes = load_notes(args.src, args.since)
        for record in notes:
            links[id(record)] = record["_folder"] if args.no_copy else copy_note(record, image_root)
        source = f"`{args.src}`"
    report = build_report(notes, args.group, links, out_file.parent, source, args.since, today)
    out_file.write_text(report, encoding="utf-8", newline="\n")
    copied = "" if (args.no_copy and not args.api) or not notes else f", Bilder in {image_root}"
    print(f"{len(notes)} Meldungen -> {out_file}{copied}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
