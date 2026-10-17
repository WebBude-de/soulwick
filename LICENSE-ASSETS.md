# Soulwick – Lizenz der Inhalte / Content licence

Code offen, Inhalte geschützt. **English below.** · Entscheidung: D-177 in
[docs/DECISIONS.md](docs/DECISIONS.md)

## Deutsch

### 1. Der Code ist frei

Der Quellcode dieses Repositorys steht unter der **GNU General Public License v3.0 oder später**
(GPL-3.0-or-later, [LICENSE](LICENSE)): GDScript, Szenen, Ressourcen, Shader, Tests, Werkzeuge und
Skripte unter `tools/`, Workflows, Dockerfile und Build-Dateien – alles außer den Inhalten aus
Abschnitt 2 (fremde Bestandteile: Abschnitt 4). Du darfst ihn lesen, ändern, weitergeben und für
eigene Spiele verwenden – unter den Bedingungen der GPL.

### 2. Die Inhalte sind ausgenommen: alle Rechte vorbehalten

© 2026 WebBude. Diese Teile stehen **nicht** unter der GPL:

| Was | Wo |
| --- | --- |
| Grafiken (Sprites, Kacheln, UI, Effekte, Store- und Web-Grafiken) | `art/` außer `art/fonts/`, `deploy/web/icons/` |
| Musik, Geräuschkulissen und Klänge | `audio/` |
| Bilder für Doku und GitHub (Mockups, Screenshots, Banner) | `docs/design/`, `.github/assets/` |
| Logo und der Name **„Soulwick“** als Kennzeichen des Spiels | überall |
| Die Figuren **Wick** (das Docht-Wesen) und **das Huhn**, ihr Aussehen und ihre Namen | überall |

Ohne schriftliche Erlaubnis von WebBude dürfen diese Inhalte nicht kopiert, verändert, weitergegeben
oder in anderen Projekten verwendet werden, außer wie in Abschnitt 3 beschrieben.

**Erzeugte Klänge:** Die Skripte `tools/generate_audio.py` und `tools/generate_music.py` sind Code
(GPL). Die Dateien in `audio/` gehören zu den Inhalten oben, auch wenn sie mit diesen Skripten erzeugt
wurden.

### 3. Was erlaubt ist

- **Selbst bauen und spielen:** Du darfst Soulwick aus diesem Repository bauen, spielen und für dich
  ausprobieren, auch mit Änderungen am Code.
- **Forken und beitragen:** Forks auf GitHub, um Änderungen vorzuschlagen, sind ausdrücklich erwünscht
  ([CONTRIBUTING.md](CONTRIBUTING.md)).
- **Eigene Spiele aus dem Code:** Wer den Code für ein eigenes Projekt nutzt und es veröffentlicht
  (Builds, Stores, Website), ersetzt alle Inhalte aus Abschnitt 2 durch **eigene** und verwendet einen
  **anderen Namen** und ein anderes Logo. Es darf nicht so aussehen, als sei es Soulwick oder ein
  offizielles Projekt von WebBude.
- **Videos, Streams und Screenshots:** Let's Plays, Streams, Clips, Reviews und Screenshots von
  Soulwick sind ausdrücklich **erlaubt und erwünscht**, auch monetarisiert (YouTube, Twitch, TikTok
  und Co.). Ein Link auf [playsoulwick.com](https://playsoulwick.com) freut uns, ist aber keine
  Pflicht. Nicht gemeint ist, Inhalte herauszulösen und einzeln zu verwerten (z. B. die Musik als
  eigenes Album, Sprites in anderen Spielen, Merchandise).

### 4. Fremde Bestandteile

Teile von anderen behalten ihre eigene Lizenz, z. B. die Schrift Pixelify Sans in `art/fonts/` (SIL
Open Font License 1.1) und das Test-Framework GUT in `addons/gut/` (MIT). Liste:
[THIRD_PARTY.md](THIRD_PARTY.md).

### 5. Fragen

Du willst etwas machen, das hier nicht steht? Schreib uns an
[hello@playsoulwick.com](mailto:hello@playsoulwick.com).

---

## English

### 1. The code is free

The source code in this repository is licensed under the **GNU General Public License v3.0 or later**
(GPL-3.0-or-later, [LICENSE](LICENSE)): GDScript, scenes, resources, shaders, tests, tools and scripts
in `tools/`, workflows, the Dockerfile and build files – everything except the content listed in
section 2 (third-party parts: section 4). You may read, change and share it and use it for your own
games under the terms of the GPL.

### 2. The content is excluded: all rights reserved

© 2026 WebBude. These parts are **not** covered by the GPL:

| What | Where |
| --- | --- |
| Artwork (sprites, tiles, UI, effects, store and web art) | `art/` except `art/fonts/`, `deploy/web/icons/` |
| Music, ambience and sound effects | `audio/` |
| Images for docs and GitHub (mockups, screenshots, banners) | `docs/design/`, `.github/assets/` |
| The logo and the name **"Soulwick"** as the name of the game | everywhere |
| The characters **Wick** (the little wick creature) and **the chicken**, their look and their names | everywhere |

Without written permission from WebBude this content may not be copied, modified, redistributed or
used in other projects, except as described in section 3.

**Generated audio:** the scripts `tools/generate_audio.py` and `tools/generate_music.py` are code
(GPL). The files in `audio/` are content as listed above, even where they were generated with these
scripts.

### 3. What you may do

- **Build and play it yourself:** you may build Soulwick from this repository, play it and experiment
  with it, including changes to the code.
- **Fork and contribute:** forks on GitHub to propose changes are welcome
  ([CONTRIBUTING.md](CONTRIBUTING.md)).
- **Your own game from the code:** if you use the code for your own project and publish it (builds,
  stores, websites), replace all content from section 2 with **your own** and use a **different name**
  and logo. It must not look like Soulwick or like an official WebBude project.
- **Videos, streams and screenshots:** let's plays, streams, clips, reviews and screenshots of Soulwick
  are explicitly **allowed and welcome**, monetized ones included (YouTube, Twitch, TikTok and the
  like). A link to [playsoulwick.com](https://playsoulwick.com) is appreciated, not required. This does
  not cover extracting content and using it on its own (for example the music as an album, sprites in
  other games, merchandise).

### 4. Third-party parts

Parts made by others keep their own licence, for example the Pixelify Sans font in `art/fonts/` (SIL
Open Font License 1.1) and the GUT test framework in `addons/gut/` (MIT). Full list:
[THIRD_PARTY.md](THIRD_PARTY.md).

### 5. Questions

Want to do something that is not covered here? Write to
[hello@playsoulwick.com](mailto:hello@playsoulwick.com).
