# Konzept Begleiter, Kosmetik und Dorf – Wick, Huhn, Pets, Deko, Besuche

> **Stand:** 17.10.2026 · **Status:** Konzept, nichts davon gebaut. Verbindlich sind nur: Wick als Maskottchen und Begleiter ab dem ersten Start, das Huhn als Neben-Maskottchen, Kosmetik für Spielfigur, Wick und Dorf (D-175); verkauft werden nur Kosmetik und Werbefrei, kein Pay-to-win, keine Lootboxen (D-176); **zum Release im Spiel** sind Wick als Begleiter, Dorf ausbauen und Freunde ins Dorf einladen (Dorf besuchen, D-179). Alles andere ist Vorschlag; offene Fragen: Abschnitt 9.
> **Pakete:** WK0–WK6 in [ROADMAP.md](ROADMAP.md) · **Grafik:** [SPRITES_V12.md](design/sprites/SPRITES_V12.md) · **Ton und Aufmachung:** D-174 (Dorf süß, gemütlich, lebendig).

## 1. Ziel

Wick und das Huhn sind das Gesicht von Soulwick (wie die Crewmates bei Among Us). Kosmetik und Dorf-Deko sind die Art, wie Spieler sich zeigen: Man spart Gold für ein schönes Dorf, zieht seinem Wick einen Hut auf und lädt Freunde ein, es anzuschauen. Nichts davon macht stärker (D-176).

## 2. Wick als Begleiter

**Absicht:** Ab dem ersten Start ist Wick, ein kleines Docht-Wesen (eine lebende Kerze mit Flamme), an deiner Seite – im Dorf, im Dungeon, in Menüs. Er ist dein Freund im Dunkeln, nicht dein Werkzeug, und gehört zum Release-Umfang (D-179). Aussehen: Konzeptblatt in SPRITES_V12 §0; eine etwas schlankere Kerze ist erlaubt, wenn er so sympathisch bleibt (D-175).

**Verhalten (Vorschlag):**

- folgt dem Spieler mit leichtem Nachziehen, schwebt und wippt, weicht nie in den Weg und verdeckt keine Gegner;
- reagiert: Freude (Raum geschafft, Upgrade), Angst (Boss-Auftritt, Dunkelheit), Neugier (Geheimnische in der Nähe, nur Optik, ohne zu verraten, was der Spieler nicht finden soll), Trauer bei „am Boden“;
- **Licht-Puls** bei wichtigen Momenten (Raum geschafft, Lagerfeuer);
- zeigt im Dorf den Weg, wo heute Hinweis-Spur und Pfeil stehen (D-161), und begrüßt beim ersten Start;
- kein Kampfwert: greift nicht an, fängt keine Treffer ab, sammelt nichts ein (Vorschlag, hält die Balance und das Koop-Bild einfach).

**Vorschlag (OFFEN): Wick ist die Quelle deines Lichtkreises.** Das Licht um den Spieler kommt sichtbar von Wicks Flamme. Die logische Sicht (`LightQuery`, D-067) bleibt am Spieler, damit sich nichts am Spiel ändert; nur das Bild folgt Wick (er schwebt dicht genug). Dafür: erzählt „Du bringst Licht ins Dunkel“ (D-174) ohne Worte, und Effekte wie Düsternis-Flüche oder Lichtfeuer bekommen eine Figur. Dagegen: Wick muss dann immer sehr nah bleiben, und eine Kosmetik-Flammenfarbe darf das Licht nicht so färben, dass Gefahr (rot) oder Ziele (kalt) verwechselt werden.

**Namenskonflikt (OFFEN):** Die Standard-Spielfigur heißt im Spiel heute schon „Wick“ (`characters/wick.tres`, Text `CHARACTER_WICK` = „Wick“, Deutsch „Docht“, D-152). Mit D-175 heißt das Maskottchen so. Vorschlag: Die Spielfigur bekommt einen neuen Anzeigenamen; die Code-ID `wick` bleibt, weil Spielstände und Konto-Profile (`PlayerAppearance.character`) sie speichern. Alternative: das Maskottchen anders nennen. Entscheidet das Projektmitglied (WK0).

## 3. Das Huhn

**Absicht:** Neben-Maskottchen (wie das Schwein bei Minecraft), taucht immer wieder mit Wick auf und sorgt für Gags. Heute schon da: Hühner im Dorf, ein Huhn als seltener Geleit-Schützling (D-120).

- **Gags mit Wick (Vorschlag):** Wick reitet auf dem Huhn; das Huhn pickt nach Wicks Flamme, Wick hüpft erschrocken; beide schlafen zusammen am Brunnen oder im Nest. Im Dorf, im Hauptmenü, beim Laden, auf Store-Bildern.
- **Im Dungeon:** selten (Dungeon-RNG), nie als Gegner. Vorschlag: Ein Huhn wird nie getötet gezeigt; scheitert ein Geleit mit Huhn, flattert es davon.
- **Party-Modus:** „Hühner einfangen“ als Minispiel (Vorschlag, [KONZEPT_PARTY_MODUS.md](KONZEPT_PARTY_MODUS.md) §4).

## 4. Pets

**Absicht:** Weitere Begleiter auf demselben Gerüst wie Wick, zum Freispielen und Zeigen (z. B. Fledermäuschen, Mini-Schleim, Glühwürmchen, Küken).

- **Regel:** reine Optik und Animation (D-176). D-175 lässt offen, ob Pets Fähigkeiten haben; Vorschlag **nein**, auch keine „kleinen Komfort-Vorteile“ wie Münzen einsammeln, weil auch das ein Spielwert wäre.
- **Wie viele:** Wick ist immer dabei; dazu höchstens ein Pet. Vorschlag: im Dorf und in der Lobby sichtbar, im Dungeon nur Wick (bei vier Spielern wären es sonst acht Begleiter vor den Gegnern).

## 5. Kosmetik

| Für | Plätze (Vorschlag) |
| --- | --- |
| Spielfigur | Kopf (Hut, Haarschmuck), Rücken (Umhang, Rucksack), Laternen- bzw. Lichtfarbe, Waffen-Aussehen später; Farben gibt es schon (D-152) |
| Wick | Hut, Flammenfarbe, kleine Spur hinter Wick |
| Dorf | Deko (Abschnitt 6), Hausfarben, Fahne, Brunnen-Aussehen |

**Regeln:**

- Nur Optik, nie ein Spielwert (D-176). Kosmetik verdeckt keine Anzeigen (Herzen, Kennzeichen, Namensschild) und ändert keine Trefferflächen.
- **Lesbarkeit im Koop:** Die Koop-Farbe jedes Spielers bleibt erkennbar (Namensschild, Ring); Licht- und Flammenfarben nur aus einer warmen, freundlichen Auswahl, nie Rot (= Gefahr) oder das kalte Ziel-Licht (R6).
- **Übertragung:** Kosmetik gehört zum Konto-Profil wie Name und Aussehen (`PATCH /me`, P-034, D-152) und kommt so zu Mitspielern, nie über Spielpakete. Gekauftes prüft der Server (D-177, CP6).
- **Grafik:** Teile mit Ankerpunkt (Kopf der Figur, Kopf von Wick), passend zu den 32×32-Figuren aller vier Figuren; erste Beispiele in SPRITES_V12.

**Freispielbar oder kaufbar (OFFEN, Vorschlag):**

| Weg | Was |
| --- | --- |
| Freispielen im Spiel | Meilensteine (erster Boss, Raum 50, jedes Biom), Erfolge, Party-Siege; Dorfladen gegen Gold oder Seelenkristalle (Spielwährung, kein Echtgeld) |
| Kaufen (D-176, ab CP6) | eigene Sets (z. B. saisonal), direkt mit sichtbarem Preis; Steam: Start-Set inklusive |
| Nie | Lootboxen, Zufallspakete, Stärke, Abkürzung von Freispielbarem gegen Geld (Vorschlag: was man freispielt, kann man nicht kaufen, und umgekehrt) |

## 6. Dorf-Deko

**Absicht:** Gold hat im Dorf einen schönen Zweck, und das Dorf wird zu etwas Eigenem (D-174). Vorschlag: zum Release, weil „Dorf ausbauen“ zum Release-Umfang gehört (D-179, Release-Tor in [ROADMAP.md](ROADMAP.md)).

- Deko kaufen (Gold), auf freie Plätze setzen, drehen, wegräumen; Wege, Türen und Gebäude bleiben frei.
- Gegenstände (Vorschlag): Blumen und Beete, Laternen, Bänke, Zäune, Statuen als Trophäen besiegter Bosse, Fahnen, Wegsteine.
- Platzierung: Vorschlag Raster auf freigegebenen Flächen statt fester Ankerpunkte (mehr Freiheit), OFFEN.
- Gespeichert je Welt (Spielstände sind Welten, D-152). Im Koop sehen alle das Dorf des Hosts mit seiner Deko.

## 6a. Zuhause betreten und einrichten

**Idee des Projektmitglieds** (Meldung #b2653f02, 17.10.2026: „Man kann Zuhause betreten und maybe kann man später ja auch für Ingame Geld oder später auch über Microtransactions hier Zuhause einrichten. Pets haben. Pets auch mit in den Fight nehmen … Merk dir das.“). Heute öffnet das Zuhause nur den Profil-Editor („Umkleiden“, D-152); einen Innenraum gibt es nicht.

**Vorschlag:**

- **Betreten:** Das Zuhause bekommt einen kleinen Innenraum als eigene Szene unter `world/village/`; durch die Tür hinein und zurück ins Dorf an dieselbe Stelle. Das Umkleiden (Spiegel, Profil-Editor) zieht dort ein.
- **Einrichten:** Möbel wie die Dorf-Deko (Abschnitt 6): kaufen, setzen, drehen, wegräumen, je Welt gespeichert. Bezahlt wird mit Gold im Spiel oder als kaufbare Kosmetik (ab CP6) – nur Optik, nie ein Spielwert (D-176); was man freispielt, kann man nicht kaufen, und umgekehrt (Abschnitt 5).
- **Pets halten:** Pets (Abschnitt 4) wohnen im Zuhause und laufen dort herum; dort wählt man, welches Pet einen begleitet.
- **Koop und Besuch:** Gäste sehen das Zuhause des Hosts mit seinen Möbeln (wie die Dorf-Deko); beim Dorf-Besuch (Abschnitt 7) gehören die Möbel (IDs mit Platz und Drehung) zum Schnappschuss.
- **Pets mit in den Kampf – OFFEN:** Das wäre Spielinhalt, nicht nur Optik, und muss gegen „kein Pay-to-win“ (D-176) geprüft werden: Ein Pet mit Wirkung im Kampf dürfte nie kaufbar sein. Auch als reine Optik stünden bei vier Spielern acht Begleiter vor den Gegnern (Abschnitt 4). Der Vorschlag bleibt: im Dungeon nur Wick, Pets nur Optik.
- **Umfang:** groß (eigene Szene, Möbel, Spielstand-Migration). Ein Paket kommt erst nach der Entscheidung in WK0 in die [ROADMAP.md](ROADMAP.md) (Vorschlag WK7 für `village-dev`, nach WK5, weil es dessen Deko-System nutzt).

## 7. Dorf besuchen

**Zum Release im Spiel** (D-179; Projektmitglied: „Dorf ausbauen … ist auch schon drin zum Release, und Freunde einladen auch“). **Zwei Wege:**

1. **Gemeinsam:** Im Koop ist man schon im Dorf des Hosts (Schnelles Spiel, Gildenraum). Das bleibt der Weg, ein Dorf zusammen anzuschauen.
2. **Ohne den Besitzer:** Ein **Schnappschuss** des Dorfs liegt auf dem Server; Freunde und Gildenmitglieder öffnen ihn aus dem Online-Menü oder der Gildenseite und laufen darin herum, **nur ansehen**, nichts ändern.

**Was übertragen wird (Vorschlag, Datenschutz-Minimum wie im Plattform-PRD §3.6):**

- schon vorhanden: Konto-ID, Anzeigename, Aussehen der Figur;
- neu: Dorf-Schnappschuss = Gebäudestufen, Deko-IDs mit Platz und Drehung, Kosmetik des Dorfs, Zeitpunkt; klein (Vorschlag ≤ 16 KB, TESTWERT);
- **nicht:** Spielstand, Gold, Statistiken, Geräte-Daten, Freitexte (keine Schilder mit eigenem Text, solange es keinen Filter gibt).

**Wer darf schauen:** Vorschlag Gildenmitglieder und wer den Besuchs-Link bzw. -Code vom Besitzer bekommt; keine öffentliche Liste. Löschen mit dem Konto (`DELETE /me`), neue Datenkategorie in der Datenschutzerklärung (eRecht24). **Melden** eines Dorfs (Deko kann auch etwas Anstößiges „schreiben“), Ausblenden im Admin-Panel.

## 8. Koop-Check und Technik-Leitplanken

- Begleiter und Pets hängen als Kind am Spieler; reine Optik, Zustand am Spieler, kein Autoload. Clients zeichnen sie aus der Spielerposition, ohne eigenes Netzpaket.
- Kosmetik über das Profil (Konto), nicht über Spielpakete; nichts davon in Spiellogik oder Trefferberechnung.
- Wick-Reaktionen hören auf vorhandene Signale (Raum geschafft, Boss-Intro, am Boden); keine neue Pause, kein `Engine.time_scale`.
- Auftritte des Huhns im Dungeon nur über den Dungeon-RNG; `randf()` nur für Optik (Wippen, Blinzeln).
- Dorf-Deko im Spielstand (Eigentümer `village-dev`), mit Migration; der Besuchs-Schnappschuss ist eine Kopie, nie der Spielstand selbst.

## 9. Offene Fragen (für WK0)

| Frage | Vorschlag |
| --- | --- |
| Endgültiger Name und Aussehen von Wick (D-175) | Name „Wick“ behalten; Docht-Wesen aus dem Konzeptblatt in SPRITES_V12 wählen (schlankere Kerze nur, wenn er so sympathisch bleibt) |
| Namenskonflikt mit der Spielfigur „Wick“ | Spielfigur bekommt neuen Anzeigenamen, Code-ID `wick` bleibt |
| Ist Wick die Quelle des Lichtkreises? | ja als Bild, logische Sicht bleibt am Spieler |
| Haben Pets Fähigkeiten? | nein, nur Optik |
| Wick und Pet im Dungeon gleichzeitig? | nein, im Dungeon nur Wick |
| Was ist freispielbar, was kaufbar? | Tabelle in Abschnitt 5; Preise OFFEN (D-176) |
| Deko frei im Raster oder auf festen Plätzen? | Raster auf freigegebenen Flächen |
| Wer darf ein Dorf besuchen, welche Welt wird gezeigt? | Gilde und Leute mit Link; die Welt, die der Besitzer als „Zuhause“ wählt |
| Huhn im Geleit verletzbar? | Herzen bleiben, aber nie als Tod gezeigt (flattert davon) |
| Zuhause als Innenraum zum Release oder später (#b2653f02)? | später, nach WK5; der Release-Umfang aus D-179 bleibt |
| Pets mit in den Kampf nehmen (#b2653f02)? | nein, im Dungeon nur Wick; ein Pet mit Wirkung im Kampf wäre nie kaufbar (D-176) |
| Möbel im Zuhause gegen Echtgeld? | ja, aber nur als Kosmetik ohne Spielwert (D-176), ab CP6; Gold-Möbel getrennt davon |

**Weiterlesen:** [ROADMAP.md](ROADMAP.md) · [PRODUKT.md](PRODUKT.md) · [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md) (CP6 Käufe) · [GLOSSAR.md](GLOSSAR.md) · [DECISIONS.md](DECISIONS.md)
