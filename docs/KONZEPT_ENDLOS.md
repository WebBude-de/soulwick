# Konzept „Endlos“ – Schwierigkeit, Biome, Meta-Progression

> **Status 15.10.2026: umgesetzt** (ROADMAP M11, D-073 bis D-079). Gültige Zahlen stehen in [DECISIONS.md](DECISIONS.md) und im Code, nicht hier: Schmiede nach D-087, Balance nach D-089 und D-118, nach jedem Boss ein Lagerfeuer mit Ausgangsportal (D-103). Die Grafikliste in §7 ist über [SPRITES_V2.md](design/sprites/SPRITES_V2.md) geliefert und nur noch historisch. Das Dokument bleibt als Begründung der Struktur (immer endlos, Biome, Schwierigkeitskurve).
>
> **Stand:** 13.10.2026 · **Anlass:** Playtest bis Raum 101: bis Raum ~90 zu leicht (Schild 120+, Facetanking, Fernkampf ohne Risiko).
> **Ziel:** Ein Endlos-Dungeon, der am Anfang fair ist, stetig schwerer wird und durch dauerhafte Dorf-Verbesserungen langfristig motiviert. Entscheidungen: D-073 bis D-079 in [DECISIONS.md](DECISIONS.md).

## 1. Struktur: immer endlos

- Es gibt **kein Ende bei Raum 45** mehr und keinen „Endlosmodus“-Dialog. Der Dungeon geht unbegrenzt weiter.
- Der Fünf-Raum-Zyklus bleibt (Kampf, Kampf, Kampf + Upgrade, Spezialraum, Miniboss).
- **Alle 15 Räume ein Boss.** Nach jedem Boss erscheint **immer ein Exit-Portal** („Checkpoint“): Gold sichern (100 %) oder weiter.
- Die 30-%-Portale in Spezialräumen bleiben bestehen.

## 2. Biome (alle 15 Räume ein neues Thema)

| Räume | Biom | Stimmung | Gegner-Schwerpunkt | Gefahr | Boss |
| --- | --- | --- | --- | --- | --- |
| 1–15 | **Krypta** | grau, Fackeln | Slime, Skelett, Bogenschütze | wenige Fallen | Knochenkönig |
| 16–30 | **Schleimgrotte** | grün, feucht | Slimes, Splitterschleim, Bomber | Giftpfützen (später, Grafik) | Schleimkönigin |
| 31–45 | **Schattenreich** | violett, sehr dunkel | Schattenwesen, Nekromant | Dunkelheit (kleiner Lichtkreis) | Schattenlord |
| 46–60 | **Glutkammer** | rot-orange | Golem, Bomber, Skelett | viele Fallen | Glutgolem |
| 61+ | Zyklus von vorn | gleiche Biome, **höhere Stufe** | gemischt | mehr | Bosse mit neuen Mustern |

Bis eigene Tiles vorhanden sind, werden Biome durch **Einfärbung** des Krypta-Tilesets, eigene Lichtfarbe und Gegner-Tabellen dargestellt.

## 3. Schwierigkeitskurve (TESTWERTE)

| Größe | Alt | Neu |
| --- | --- | --- |
| Gegner pro Kampfraum | 1–3, ab 25: 2–3 | R1–3: 1–2 · R4–14: 2–3 · R15–29: 2–4 · R30+: 3–5 |
| Gegner-HP je 5er-Block | ×1,20 | ×1,18 (mehr Gegner gleichen aus) |
| Gegner-Schaden je Block | ×1,10 | **×1,14** |
| Angriffstempo je Block | – | Abklingzeit −3 % (min. 55 %), Telegraph −1,5 % (min. 70 %) |
| Lauftempo je Block | – | +2 % (max. +40 %) |
| Elite-Chance | 12 % + 1 %/Block | 12 % + **2 %**/Block, max. 50 % |
| Fernkämpfer-Anteil | fest 15 % | steigt je Biom |
| Schildverstärkung | +10 | **+4** |
| Schild bei Tötung | +2/Stack | **+0,5/Stack** |
| Heilung bei Tötung | +2/Stack | **+0,5/Stack** |
| Shop-Schild | +4 | **+3** |
| Schild-Softcap | ab 50 halbiert | **ab 15 halbiert** |

Anfang bleibt fair: Raum 1–3 haben 1–2 Gegner, Block 0 hat keine Beschleunigung.

## 4. Bosse werden komplexer

Bossnummer `n = Raum / 15`. Reihenfolge Knochenkönig → Schleimkönigin → Schattenlord → Glutgolem → von vorn. **Stufe** `t = floor((n − 1) / 4)`:

- jede Stufe: +40 % Boss-HP zusätzlich zur Block-Skalierung
- ab Stufe 1: Salven +6 Geschosse, Spezialangriff öfter
- ab Stufe 2: Bosse beschwören zusätzlich Diener

## 5. Neue Gegner

| Gegner | Verhalten | Grafik vorerst |
| --- | --- | --- |
| **Splitterschleim** | teilt sich beim Tod in 2 Mini-Schleime | Slime, grün |
| **Golem** | langsam, viel HP, Stampfer mit Schockwelle, kaum Rückstoß | Skelett, steingrau, groß |
| **Nekromant** | hält Abstand, Fluch-Geschosse, beschwört Skelette | Bogenschütze, grünlich |
| **Glutgolem** (Boss) | Stampfer, Feuer-Salven, beschwört Bomber | Skelett, glühend, sehr groß |

## 6. Meta-Progression im Dorf (Schmiede)

Permanentes Gold wird in der **Schmiede** im Dorf ausgegeben (E am Gebäude). Wirkung in jedem neuen Run.

> **Gültige Werte: [D-087](DECISIONS.md)** (seit 14.10.2026, Spielstand v3, B2). 28 → 20 Stufen, Kristall-Tausch entfällt, Goldgier/Dash-Training/Arsenal erst nach dem ersten besiegten Boss. Quelle im Code: `MetaProgression.UPGRADES` (`meta/meta_progression.gd`), Freischaltungen in `meta/meta_unlocks.gd`.

| Verbesserung | pro Stufe | Stufen | Kosten (Gold) |
| --- | --- | --- | --- |
| Vitalität | +1 Max-HP | 5 | 40 · 80 · 140 · 220 · 320 |
| Startschild | +3 Schild beim Start | 3 | 40 · 90 · 160 |
| Schärfe | +10 % Schaden | 4 | 70 · 150 · 260 · 400 |
| Goldgier | +15 % Gold-Drops | 3 | 60 · 140 · 250 |
| Dash-Training | −0,15 s Dash-Abklingzeit | 3 | 60 · 140 · 260 |
| Arsenal | Bogen bzw. Stab als zweite Startwaffe | 2 | 80 · 160 |

Frühere Fassung (bis Spielstand v2): Startschild 5 × 2, Schärfe 8 × 5 %, Goldgier 5 × 10 %; alte Stufen rechnet `SaveManager.migrate()` beim Laden um (D-087).

## 7. Benötigte Grafiken (für Claude Design)

Gleiche Formatregeln wie in [SPRITES.md](design/sprites/SPRITES.md). Tilesets **exakt im Layout** von `dungeon_tileset.png` (8×3 Tiles à 32 px, gleiche Reihenfolge).

**Biome**
- [ ] `slime_grotto_tileset.png` – grünliche, feuchte Höhle, Moos, Pfützen
- [ ] `shadow_realm_tileset.png` – violett-schwarzer Stein, Risse mit Leuchten
- [ ] `ember_forge_tileset.png` – dunkler Stein, Glutadern, Asche
- [ ] Fackel-Varianten (32×32, 4 Frames): `torch_green_4f.png`, `torch_purple_4f.png`, `brazier_4f.png`
- [ ] Bodengefahren (32×32): `toxic_puddle_4f.png`, `lava_crack_4f.png`

**Gegner** (32×32, Animationen idle/walk/attack/death)
- [ ] Splitterschleim + Mini-Schleim (16×16 oder 32×32)
- [ ] Golem (32×32 oder 48×48)
- [ ] Nekromant
- [ ] Schattenwesen, Bomber (falls noch nicht geliefert)

**Bosse** (64×64, idle/walk/attack/attack2/death)
- [ ] Knochenkönig, Schleimkönigin, Schattenlord, Glutgolem

**Dorf**
- [ ] Schmied-NPC (32×32, idle 4 Frames), Amboss (32×32)
- [ ] 6 Icons (16×16) für die Meta-Verbesserungen: Herz+, Schild+, Klinge, Goldsack, Stiefel, Waffenständer
