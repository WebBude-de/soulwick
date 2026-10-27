# Antwort auf V13 – Rückmeldung vom 22.10. (Flint, Rang, Maßstab)

## Umbenennung
- Der Begleiter heißt **Flint**. Ablage `art/companions/flint/`, Dateien `flint_<anim>_<n>f.png`, `flint.json` (Anker `flame`/`head` je Frame unter `anchors_per_frame`), Masken `flint_flame_mask_<anim>_<n>f.png`. Die Spielfigur mit ID `wick` bleibt unberührt.
- Mockups 13–17 sowie `wick_concept_sheet*.png` zeigen noch den alten Namen; Entwurf A wurde gewählt und für die Spielgröße neu gezeichnet.

## Maßstab (Screenshot vom 22.10.)
- Im Screenshot ist die Spielfigur 26 px hoch (×3 gezeichnet). Flint ist jetzt **≈ 12 px** (Körper 8×7, Flamme 4–5 px) im 16×16-Frame, Pivot (8,15): Katzengröße, eindeutig ein kleines Pet.
- Empfehlung Kamera: Zoom im Dorf und Dungeon von 3,0 auf **3,5** (Godot `Camera2D.zoom`), Lichtkreis auf 5 Kacheln begrenzen. Dadurch wirken Figuren und Flint größer, ohne neue Sprites; HUD bleibt in Bildschirmpixeln. Hochkant-Handy: Zoom 3,0 beibehalten, aber UI-Skalierung 2.
- Flint schwebt 6 px über Fußhöhe der Spielfigur, Position 10 px links hinter ihr; beim Zeigen (`point`) wechselt er auf die rechte Seite.

## Detailgrad
- Flint hat jetzt zwei Wachs-Lichtkanten, dunklere Wachsbasis, 2×2-Augen mit Glanzpunkt, Wangen, Mund, violettes Band und Füßchen. Für die große Fassung (Erklär-Ecke 48×48, Menü 96×96, Hero 128×128) wird Flint **neu in höherer Auflösung gezeichnet**, nicht hochskaliert, mit Wachstropfen, Dochtfaser, Flammenkern und Zunge (B2, Lieferung mit Teil B).

## Rang steuert die Gefahr (statt manueller Stufe)
- Der Dialog „Gefahr wählen“ entfällt. Am Eingang steht nur: **Rang des Squads** (Durchschnitt der Spieler-Ränge, im schnellen Spiel aus dem Matchmaking) → daraus Gefahrenstufe und Beutebonus, als Anzeige, nicht als Wahl.
- Abzeichen zeigen die **Stufe sichtbar**: Rang-Symbol + 3 Stufenmarken (gefüllt / leer) darunter; XP-Balken im Run-Ende füllt die Marken, Abstieg leert sie wieder (Animation `rank_pips_down`). Vorschlag: Verlust nur bei Tod ohne Sicherung, nie unter die erste Marke eines Rangs (Rang bleibt, Marke fällt).
- Mockup A5 wird entsprechend angepasst: links „Squad-Rang: Kerze II · Gefahr 4 · +15 % Beute“ als Infokarte mit den Porträts und Rängen der Mitspieler, rechts „E Hinabsteigen“.

## Offene Rückfragen (kurz)
- Rahmen des Porträts: ich nehme den **runden Rahmen** (schnell lesbar in der Ecke, passt zur Flamme); Kerzenhalter-Form als Variante im B2-Blatt.
- Zuhause innen: Mockup 14 steht bereit (Dielen, Mondfenster, Kamin, Altar); Änderungen gern nach Sichtung.
