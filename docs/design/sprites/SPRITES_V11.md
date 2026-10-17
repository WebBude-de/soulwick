# Grafik-Briefing V11 – Soulwick: Store-Grafiken (Google Play, App Store, Steam)

> **Für Claude Design.** Grafiken für die Store-Seiten und das App-Icon in voller Größe. Quelle der Maße ist die Tabelle unten (nur hier); Texte, Screenshots und Trailer stehen in [STORES.md §6](../../STORES.md).
> **Stand:** 17.10.2026 · **geliefert** (alle 16 Dateien in `art/store/`) · Ablage: `art/store/` mit genau diesen Namen (Lieferung wie immer nach `_inbox/`).
>
> **Lieferstand 17.10.2026:** Maße und Transparenz stimmen (nur `steam_library_logo` und Adaptive-Vordergrund/Monochrom transparent). `steam_community_icon.jpg` war ein PNG mit falscher Endung und ist beim Übernehmen in ein echtes JPG (Grund `#15131f`) gewandelt. `art/store/` hat ein `.gdignore`: Godot importiert und exportiert die 7 MB nicht in die Spiel-Builds. Wer `icon_1024.png` bzw. `android_adaptive_*` im iOS-/Android-Preset einträgt (`tools/ci/store_presets.py`, `export_presets.cfg`), muss diese Dateien dafür an eine importierte Stelle legen oder das `.gdignore` durch einen `exclude_filter` ersetzen. Gestaltung zum Nachschärfen: In `steam_header_capsule` und `steam_library_header` überdecken sich Spieler, Schleim und Skelett; in `play_feature_1024x500` ist der Mond am Rand angeschnitten.

## Regeln

- Motiv: Kerze mit violettem Seelen-Kristall (wie die gelieferten App-Icons in `deploy/web/icons/` und `art/ui/logo_square.png`), dunkler Grund `#15131f`, Palette aus [HANDOUT.md](../../HANDOUT.md).
- Pixel-Art **ganzzahlig** hochskaliert (nearest neighbor), kein Weichzeichnen; große Flächen dürfen gemalt sein, Figuren und Logo bleiben Pixel-Art.
- Kein Text im Bild außer dem Schriftzug „SOULWICK“ (wie im Hauptmenü); keine Engine-, Server- oder Technik-Begriffe.
- Ohne Transparenz, außer wo es dabei steht (`steam_library_logo`).
- Wichtiges nie an den Rändern (Stores schneiden und runden).
- **Screenshots** sind nicht Teil dieses Briefings: die nimmt Claude aus dem echten Spiel auf (`tools/screenshots.gd`).

## Dateien

| Datei | Maße | Format | Store | Inhalt |
| --- | --- | --- | --- | --- |
| `art/store/icon_1024.png` | 1024×1024 | PNG **ohne Transparenz** | Apple (im Spiel-Bundle), Quelle für alle | App-Icon (Kerze + Kristall), Motiv in den mittleren 80 %; ersetzt das Übergangs-Icon im iOS-Preset |
| `art/store/play_icon_512.png` | 512×512 | PNG 32 Bit, ≤ 1 MB | Google Play | wie oben; Google rundet die Ecken selbst |
| `art/store/android_adaptive_fg_432.png`, `…_bg_432.png`, `…_mono_432.png` | je 432×432 | PNG | Android (im Spiel) | adaptives Icon: Vordergrund mit Motiv in den mittleren 66 %, Hintergrund flach, Monochrom-Version; heute nutzt das Preset nur das 64-px-Logo |
| `art/store/play_feature_1024x500.png` | 1024×500 | PNG/JPG ohne Transparenz | Google Play | Feature-Grafik: Logo/Schriftzug + Szene; wichtige Teile nicht an den Rändern |
| `art/store/steam_header_capsule.png` | 920×430 | PNG/JPG | Steam | Kopf-Kapsel: Logo gut lesbar |
| `art/store/steam_small_capsule.png` | 462×174 | PNG/JPG | Steam | kleine Kapsel: nur Logo, muss winzig lesbar bleiben |
| `art/store/steam_main_capsule.png` | 1232×706 | PNG/JPG | Steam | Haupt-Kapsel (Startseite) |
| `art/store/steam_vertical_capsule.png` | 748×896 | PNG/JPG | Steam | senkrechte Kapsel (Aktionen) |
| `art/store/steam_library_capsule.png` | 600×900 | PNG/JPG | Steam | Bibliothek, Hochformat |
| `art/store/steam_library_header.png` | 920×430 | PNG/JPG | Steam | Bibliothek, Kopf |
| `art/store/steam_library_hero.png` | 3840×1240 | PNG/JPG | Steam | Bibliothek, Hintergrund **ohne** Logo/Text, Motiv mittig |
| `art/store/steam_library_logo.png` | 1280×720 (Logo ≤ 1280 breit oder ≤ 720 hoch) | PNG **mit** Transparenz | Steam | Schriftzug über dem Hero |
| `art/store/steam_page_background.png` | 1438×810 | PNG/JPG | Steam (optional) | dunkle, ruhige Fläche |
| `art/store/steam_community_icon.jpg` | 184×184 | JPG | Steam | quadratisches Icon |

## Was der Code damit macht

- `icon_1024.png` ersetzt im iOS-Export das Übergangs-Icon (`tools/ci/store_presets.py`); `android_adaptive_*` werden ins Android-Preset übernommen, sobald sie da sind (heute 64-px-Logo).
- Alle übrigen Dateien lädt das Projektmitglied in Play Console, App Store Connect bzw. Steamworks hoch (Schritte in [STORES.md](../../STORES.md)).
