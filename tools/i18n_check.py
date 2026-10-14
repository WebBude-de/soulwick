#!/usr/bin/env python3
"""Findet deutsche Texte in *.gd und *.tscn, die noch keine Uebersetzungsschluessel sind (D-111).

Aufruf (im Repo-Root):
    python tools/i18n_check.py ui/options ui/main_menu       # Ordner pruefen, Exit 1 bei Funden
    python tools/i18n_check.py --summary .                   # nur Anzahl je Ordner (Backlog)
    python tools/i18n_check.py --tres village                # auch *.tres (Datenressourcen) mitzaehlen
    python tools/i18n_check.py --dungeon-texts               # DungeonTexts-Schluessel ohne Englisch melden
    python tools/i18n_check.py --dungeon-texts --export      # ... und fehlende Zeilen fuer die CSV ausgeben

Zusaetzlich prueft es localization/translations.csv (leere Zellen, doppelte Schluessel, gleiche
Platzhalter in en und de); Fehler dort fuehren ebenfalls zu Exit 1 (--no-csv schaltet das ab).
Erkennung: Umlaute/ss oder ein eindeutig deutsches Wort aus GERMAN_WORDS in einem String-Literal.
In *.tres zaehlen Anzeigefelder nicht, deren Schluessel nach Namenskonvention in der CSV steht
(UpgradeData: UPGRADE_<ID>_NAME/_DESC, WeaponData: WEAPON_<ID>_NAME/_SPECIAL/_SPECIAL_DESC, DataTexts).
--dungeon-texts vergleicht die Tabelle DungeonTexts.DE (ui/menus/dungeon_texts.gd) mit der CSV:
Schluessel ohne CSV-Zeile oder ohne Englisch und abweichendes Deutsch (Exit 1 bei Funden).
Uebersprungen werden Kommentare, &"StringName", ^"NodePath", Pfade, Bezeichner, Schluessel
(GROSS_SCHREIBUNG) und reine Format-/Zahlenstrings. addons/ und .godot/ werden nie durchsucht.
"""
import argparse
import csv
import io
import os
import re
import sys

EXCLUDED_DIRS = {"addons", ".godot", ".git", "__pycache__", "node_modules"}
UMLAUT_RE = re.compile(r"[äöüÄÖÜß]")
WORD_RE = re.compile(r"[A-Za-zÄÖÜäöüß]+")
PLACEHOLDER_RE = re.compile(r"%[sdf]|%\d*\.\d+f|\{\w+\}")
KEY_RE = re.compile(r"^[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+$")
IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9_./:%\-\[\]*+#]*$")
TSCN_PROPERTY_RE = re.compile(r'^\s*([A-Za-z_]+)\s*=\s*"((?:[^"\\]|\\.)*)"')
DUNGEON_TEXTS_PATH = "ui/menus/dungeon_texts.gd"
DUNGEON_TEXTS_ENTRY_RE = re.compile(r'^\s*&"([A-Z0-9_]+)":\s*"((?:[^"\\]|\\.)*)",?\s*$')
TRES_CLASS_RE = re.compile(r'script_class="(\w+)"')
TRES_ID_RE = re.compile(r'^id\s*=\s*&?"(\w+)"')
# Datenklasse -> (Schluessel-Praefix, Feld -> Schluessel-Endung); Gegenstueck: localization/data_texts.gd
TRES_KEY_FIELDS = {
    "UpgradeData": ("UPGRADE", {"display_name": "NAME", "description": "DESC"}),
    "WeaponData": ("WEAPON", {"display_name": "NAME", "special_name": "SPECIAL", "special_description": "SPECIAL_DESC"}),
}
TSCN_TEXT_PROPERTIES = {"text", "tooltip_text", "placeholder_text", "title", "dialog_text", "hint_tooltip", "ok_button_text", "cancel_button_text"}

# Eindeutig deutsche Woerter (keine englischen Homonyme wie die/an/am/bald/hat/gold/held/was/gut/tag).
GERMAN_WORDS = set("""
der den dem des ein eine einen einem einer eines und oder nicht kein keine keinen keinem keiner
mit ohne für von zu zum zur auf aus bei nach über unter vor hinter im ins beim noch schon wieder
mehr sehr auch nur ist sind wird werden haben kann kannst wählen wähle zurück abbrechen weiter
spielen spiel spielstand spielstände raum räume gegner waffe waffen schaden leben dorf neu neue
neuer neues anlegen löschen beenden pausiert optionen einstellungen tasten taste steuerung
lautstärke musik effekte fenster vollbild bestätigen leertaste drücke drücken halten öffnen
schließen kaufen verkaufen preis händler schmied gilde chronik zuhause lagerfeuer truhe prüfung
nächster nächste nächstes letzte letzter letztes erste erster erstes zweite dritte rechts oben
unten dein deine deinen deinem deiner du dich dir wir uns ihr sie ja nein heute jetzt hier dort
wenn dann weil aber doch mal sofort später bereit fertig verloren gewonnen tot getötet besiegt
gefallen verlassen abgebrochen betreten stirbt bleibt bleiben kommt kommen geht gehen gibt geben
wirklich alles nichts etwas viel wenig schlecht schnell langsam stark schwach groß klein kurz
alle jeder jede jedes dieser diese dieses welche welcher welches wie wo wer warum erneut nochmal
zurücksetzen ändern wechseln benutzen zielen angreifen bewegen ausweichen werte sicht dunkel licht
seele seelen docht kristall kristalle schild herz herzen stufe stufen freigeschaltet freischalten
gesperrt belegt leer platz farbe charakter abschließen verbleibend übrig restlich bezahlen
erhalten erhältst bekommst bekommen verlierst verliert behältst behalten sammeln gesammelt
getroffen treffer schlag schläge angriff angriffe verteidigung rüstung heilung geheilt heilen
tränke trank zauber fluch segen opfer pakt altar portal lagerfeuer rast rasten weg wege tür türen
schlüssel ausgang eingang tiefe tief ebene ebenen zyklus welle wellen gegnerwelle arena falle
fallen abgrund brücke boden wand wände mauer mauern fackel kiste kisten schatz schätze belohnung
belohnungen auswahl wahl entscheidung entscheide zeit sekunden minuten stunden heute gestern
willkommen danke bitte achtung vorsicht hinweis hinweise tipp tipps erklärung erklärungen
""".split())


def transliterate(text):
    return (text.replace("ä", "ae").replace("ö", "oe").replace("ü", "ue").replace("ß", "ss")
            .replace("Ä", "AE").replace("Ö", "OE").replace("Ü", "UE"))


def looks_german(text):
    if UMLAUT_RE.search(text):
        return True
    for word in WORD_RE.findall(text):
        if word.lower() in GERMAN_WORDS:
            return True
    return False


def is_candidate(text):
    stripped = text.strip()
    if len(stripped) < 2 or not WORD_RE.search(stripped):
        return False
    if "://" in stripped or stripped.startswith(("res:", "user:", "uid:")):
        return False
    if KEY_RE.match(stripped):
        return False
    if IDENTIFIER_RE.match(stripped) and " " not in stripped:
        return False
    return looks_german(stripped)


def gd_string_literals(line):
    """Liefert (prefix, text) fuer jedes String-Literal der Zeile; Kommentare werden ignoriert."""
    literals = []
    i = 0
    n = len(line)
    while i < n:
        ch = line[i]
        if ch == "#":
            break
        if ch in "\"'":
            quote = ch
            prefix = line[i - 1] if i > 0 else ""
            j = i + 1
            buf = []
            while j < n:
                c = line[j]
                if c == "\\" and j + 1 < n:
                    buf.append(line[j:j + 2])
                    j += 2
                    continue
                if c == quote:
                    break
                buf.append(c)
                j += 1
            literals.append((prefix, "".join(buf)))
            i = j + 1
            continue
        i += 1
    return literals


def suggest_key(path, text):
    parts = path.replace("\\", "/").split("/")
    top = parts[0] if len(parts) > 1 else ""
    stem = os.path.splitext(parts[-1])[0]
    domain_by_top = {
        "village": "VILLAGE", "dungeon": "DUNGEON", "enemies": "ENEMY", "player": "PLAYER",
        "weapons": "WEAPON", "upgrades": "UPGRADE", "meta": "META", "characters": "CHARACTER",
        "scenes": "SCENE", "tools": "TOOL", "tests": "TEST", "components": "COMPONENT",
    }
    if top == "ui" and len(parts) > 2:
        sub = parts[1]
        domain = {"hud": "HUD", "hints": "HINT", "boss_intro": "BOSS_INTRO", "options": "OPTIONS",
                  "main_menu": "MENU", "damage_numbers": "DAMAGE", "effects": "FX",
                  "widgets": "UI"}.get(sub, stem.upper())
        if sub == "menus":
            domain = stem.upper()
    else:
        domain = domain_by_top.get(top, stem.upper())
    words = [w for w in WORD_RE.findall(transliterate(PLACEHOLDER_RE.sub(" ", text)))][:3]
    slug = "_".join(w.upper() for w in words) or "TEXT"
    return "%s_%s" % (domain, slug)


def scan_gd(path, rel, translated_keys=frozenset()):
    findings = []
    with io.open(path, encoding="utf-8", errors="replace") as handle:
        for number, line in enumerate(handle, 1):
            # DungeonTexts.DE is the German source table: entries with English in the CSV are done.
            if rel == DUNGEON_TEXTS_PATH:
                entry = DUNGEON_TEXTS_ENTRY_RE.match(line)
                if entry and entry.group(1) in translated_keys:
                    continue
            for prefix, text in gd_string_literals(line):
                if prefix in ("&", "^"):
                    continue
                if is_candidate(text):
                    findings.append((rel, number, text))
    return findings


def scan_tscn(path, rel):
    findings = []
    with io.open(path, encoding="utf-8", errors="replace") as handle:
        for number, line in enumerate(handle, 1):
            match = TSCN_PROPERTY_RE.match(line)
            if not match:
                continue
            name, text = match.group(1), match.group(2)
            if name in TSCN_TEXT_PROPERTIES or name.endswith("_text"):
                if is_candidate(text):
                    findings.append((rel, number, text))
    return findings


def scan_tres(path, rel, csv_keys=frozenset()):
    findings = []
    with io.open(path, encoding="utf-8", errors="replace") as handle:
        lines = handle.readlines()
    # Anzeigefelder mit Schluessel nach Namenskonvention (DataTexts) gelten als uebersetzt.
    covered = {}
    class_match = TRES_CLASS_RE.search(lines[0]) if lines else None
    if class_match and class_match.group(1) in TRES_KEY_FIELDS:
        prefix, fields = TRES_KEY_FIELDS[class_match.group(1)]
        for line in lines:
            id_match = TRES_ID_RE.match(line)
            if id_match:
                for field, suffix in fields.items():
                    covered[field] = "%s_%s_%s" % (prefix, id_match.group(1).upper(), suffix)
    for number, line in enumerate(lines, 1):
        match = TSCN_PROPERTY_RE.match(line)
        if match and covered.get(match.group(1)) in csv_keys:
            continue
        if match and is_candidate(match.group(2)):
            findings.append((rel, number, match.group(2)))
        elif "PackedStringArray(" in line or "Array[String](" in line:
            for text in re.findall(r'"((?:[^"\\]|\\.)*)"', line):
                if is_candidate(text):
                    findings.append((rel, number, text))
    return findings


def walk(root, folder, include_tres):
    base = os.path.join(root, folder)
    if os.path.isfile(base):
        yield base
        return
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = sorted(d for d in dirnames if d not in EXCLUDED_DIRS)
        for name in sorted(filenames):
            if name.endswith((".gd", ".tscn")) or (include_tres and name.endswith(".tres")):
                yield os.path.join(dirpath, name)


def read_csv(root, csv_path):
    """{key: {locale: text}} der Uebersetzungstabelle (leer, wenn sie fehlt)."""
    full = os.path.join(root, csv_path)
    if not os.path.isfile(full):
        return {}
    with io.open(full, encoding="utf-8", newline="") as handle:
        rows = list(csv.reader(handle))
    if not rows:
        return {}
    header = [cell.strip() for cell in rows[0]]
    table = {}
    for row in rows[1:]:
        if row and row[0].strip():
            table[row[0].strip()] = {header[i]: row[i] for i in range(1, min(len(header), len(row)))}
    return table


def read_dungeon_texts(root):
    """[(key, deutscher Text)] aus DungeonTexts.DE, Reihenfolge wie in der Datei."""
    entries = []
    full = os.path.join(root, DUNGEON_TEXTS_PATH)
    if not os.path.isfile(full):
        return entries
    with io.open(full, encoding="utf-8") as handle:
        for line in handle:
            match = DUNGEON_TEXTS_ENTRY_RE.match(line)
            if match:
                entries.append((match.group(1), match.group(2).replace('\\"', '"')))
    return entries


def csv_line(key, en, de):
    return '%s,"%s","%s"' % (key, en.replace('"', '""'), de.replace('"', '""'))


def check_dungeon_texts(root, csv_path, export):
    """Meldet DungeonTexts-Schluessel ohne Englisch in der CSV und Deutsch, das von DE abweicht."""
    table = read_csv(root, csv_path)
    entries = read_dungeon_texts(root)
    missing = [(key, de) for key, de in entries if not table.get(key, {}).get("en", "").strip()]
    changed = [(key, de) for key, de in entries
               if table.get(key, {}).get("en", "").strip() and table[key].get("de", "") != de]
    print("DungeonTexts: %d Schluessel, %d ohne Englisch, %d mit abweichendem Deutsch"
          % (len(entries), len(missing), len(changed)))
    for key, _de in missing:
        print("  ohne Englisch: %s" % key)
    for key, de in changed:
        print('  Deutsch weicht ab: %s (DungeonTexts "%s", CSV "%s")' % (key, de, table[key].get("de", "")))
    if export and (missing or changed):
        print("# Zeilen fuer %s: Englisch eintragen; vorhandene Zeilen desselben Schluessels ersetzen." % csv_path)
        for key, de in missing:
            print(csv_line(key, table.get(key, {}).get("en", ""), de))
        for key, de in changed:
            print(csv_line(key, table[key].get("en", ""), de))
    return 1 if missing or changed else 0


def check_csv(root, csv_path):
    problems = []
    full = os.path.join(root, csv_path)
    if not os.path.isfile(full):
        return ["%s fehlt" % csv_path]
    with io.open(full, encoding="utf-8", newline="") as handle:
        rows = list(csv.reader(handle))
    if not rows or len(rows[0]) < 3:
        return ["%s: Kopfzeile keys,en,de erwartet" % csv_path]
    header = rows[0]
    seen = set()
    for number, row in enumerate(rows[1:], 2):
        if not row or not row[0].strip():
            continue
        key = row[0].strip()
        if not KEY_RE.match(key):
            problems.append("%s:%d: Schluessel %r nicht GROSS_SCHREIBUNG" % (csv_path, number, key))
        if key in seen:
            problems.append("%s:%d: Schluessel %s doppelt" % (csv_path, number, key))
        seen.add(key)
        if len(row) < len(header):
            problems.append("%s:%d: %s hat zu wenige Spalten" % (csv_path, number, key))
            continue
        cells = row[1:len(header)]
        for locale, cell in zip(header[1:], cells):
            if not cell.strip():
                problems.append("%s:%d: %s hat keinen Text fuer %s" % (csv_path, number, key, locale))
        counts = [sorted(PLACEHOLDER_RE.findall(cell)) for cell in cells]
        if any(c != counts[0] for c in counts[1:]):
            problems.append("%s:%d: %s hat verschiedene Platzhalter: %s" % (csv_path, number, key, counts))
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("folders", nargs="*", default=["."], help="Ordner oder Dateien relativ zum Repo-Root")
    parser.add_argument("--summary", action="store_true", help="nur Anzahl je Ordner ausgeben")
    parser.add_argument("--tres", action="store_true", help="auch *.tres durchsuchen")
    parser.add_argument("--no-csv", action="store_true", help="translations.csv nicht pruefen")
    parser.add_argument("--dungeon-texts", action="store_true",
                        help="nur DungeonTexts.DE gegen die CSV pruefen (Schluessel ohne Englisch)")
    parser.add_argument("--export", action="store_true",
                        help="mit --dungeon-texts: fehlende/abweichende Zeilen im CSV-Format ausgeben")
    parser.add_argument("--csv", default="localization/translations.csv")
    parser.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    args = parser.parse_args()
    if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    root = os.path.abspath(args.root)
    if args.dungeon_texts:
        return check_dungeon_texts(root, args.csv, args.export)
    table = read_csv(root, args.csv)
    csv_keys = frozenset(table) if args.tres else frozenset()
    translated_keys = frozenset(key for key, texts in table.items() if texts.get("en", "").strip())
    findings = []
    for folder in args.folders:
        for path in walk(root, folder, args.tres):
            rel = os.path.relpath(path, root).replace("\\", "/")
            if path.endswith(".gd"):
                findings.extend(scan_gd(path, rel, translated_keys))
            elif path.endswith(".tscn"):
                findings.extend(scan_tscn(path, rel))
            else:
                findings.extend(scan_tres(path, rel, csv_keys))

    per_folder = {}
    for rel, _number, _text in findings:
        parts = rel.split("/")
        group = "/".join(parts[:2]) if parts[0] == "ui" and len(parts) > 2 else parts[0]
        per_folder[group] = per_folder.get(group, 0) + 1

    if not args.summary:
        for rel, number, text in findings:
            print('%s:%d: "%s" -> %s' % (rel, number, text, suggest_key(rel, text)))
    print("deutsche Texte je Ordner:")
    for group in sorted(per_folder):
        print("  %-24s %4d" % (group, per_folder[group]))
    print("gesamt: %d" % len(findings))

    exit_code = 1 if findings else 0
    if not args.no_csv:
        problems = check_csv(root, args.csv)
        for problem in problems:
            print("CSV: " + problem)
        if problems:
            exit_code = 1
        else:
            print("CSV ok: %s" % args.csv)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
