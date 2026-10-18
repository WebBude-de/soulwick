# Soulwick – Produktüberblick

> **Stand:** 17.10.2026 · **Gilt für beide Repositories:** `soulwick` (Spiel) und `soulwick-platform` (Online-Teil).
> **Zweck:** Was Soulwick sein soll, für wen und warum, an **einer** Stelle. Was schon gebaut ist, steht im Code, nicht hier (D-178). Begriffe: [GLOSSAR.md](GLOSSAR.md). Entscheidungen: [DECISIONS.md](DECISIONS.md). Was als Nächstes kommt: [ROADMAP.md](ROADMAP.md).
> **Leseregel:** `OFFEN` = noch nicht entschieden; nichts in dieser Datei legt eine offene Frage fest.

## 1. Was ist Soulwick

Ein Pixel-Roguelite, in das man mit Freunden reinrennt: Top-down, direkte Action mit Maus, Touch oder Gamepad, ein endloser Dungeon mit Biomen, Bossen und Minispiel-Räumen, dazu ein Dorf, das man ausbaut, verschönert und anderen zeigt. Gebaut in Godot 4.7.2, Online-Teil in `soulwick-platform`.

- **Name:** Soulwick (Docht + Seele, D-094). Das Licht ist das Motiv: Du bringst Licht in den Dungeon.
- **Tagline** (D-174, Arbeitsfassung): „Grab your friends. Light the dark.“ / „Schnapp dir deine Freunde. Bring Licht ins Dunkel.“
- **Herkunft:** Idee eines Kollegen des Projektmitglieds, Teamprojekt. Nach außen „Made with ♥ by WebBude“. Website: playsoulwick.com (D-111).

## 2. Positionierung (D-173)

**Kernsatz:** Das Pixel-Roguelite, in das du mit Freunden reinrennst – jeder Run anders, jeder Boss ein Clip.

**Das Gefühl, das wir wollen:** wie Among Us, als es rauskam. Ein Spiel, das man in einer Minute versteht, mit Freunden sofort startet, in dem ständig etwas Lustiges oder Verrücktes passiert und das man deshalb teilt. Es wird laufend erweitert (neue Minispiele, neue Bosse, neue Modi), damit es interessant bleibt.

**Leicht zu lernen, schwer zu meistern:** Die ersten Räume schafft jeder. Tief im Dungeon, in den Ranglisten und bei hohen Schwierigkeiten lohnt sich Können; wer will, kann sich reinsweaten.

**Zielgruppe:**

- **Kern:** 12 bis 25 Jahre, Freundesgruppen, die zusammen zocken (Discord, Schulhof, nach der Arbeit eine halbe Stunde). Allein spielen geht, ist aber nicht das, wofür man Soulwick kennt.
- **Offiziell:** Store-Zielgruppe ab 13; wir bewerben das Spiel nicht an Kinder unter 12 und melden es nicht für Kinder-Bereiche der Stores an (Google Play Familienprogramm, Apple Kids). Jüngere spielen trotzdem mit, weil sie es über TikTok und Freunde finden; deshalb bleibt der Inhalt harmlos (kein Blut, keine Lootboxen, Moderation bei KI-Inhalten).
- **Altersfreigabe:** ergibt sich aus dem IARC-Fragebogen der Stores, nicht aus unserer Wahl; erwartet niedrig (Pixel-Kampf ohne Blut). OFFEN: ob KI-Bosse, Kosmetik-Käufe und Koop mit Fremden die Freigabe anheben.
- **Sprache:** international, Englisch Standard, Deutsch zweite Sprache (D-111).

**Vergleiche, die wir benutzen dürfen:**

| Spiel | Was wir davon wollen |
| --- | --- |
| Among Us | Gefühl, Einstieg, Clips, Spielfigur als Maskottchen, Kosmetik |
| Soul Knight | engster Genre-Nachbar (Pixel-Roguelite, Koop, Handy). Unser Unterschied: Minispiel-Räume, KI-Bosse, Crossplay PC/Handy/Browser, Dorf zum Zeigen |
| Stardew Valley | Lebendigkeit und Gemütlichkeit des Dorfs |
| Dead Cells, Eastward, Celeste | moderne Pixel-Art: Licht, Bewegung, Feinschliff |

## 3. Ton und Aufmachung (D-174)

- **Dungeon:** spannend und atmosphärisch, darf düster sein (wie das Raumschiff in Among Us), wird aber nie ernst oder lächerlich. Das Licht des Spielers ist warm und positiv.
- **Dorf:** süß, gemütlich, lebendig. Hier gibt man gern Gold und Geld aus, verschönert sein Dorf und lädt Freunde ein, es anzuschauen.
- **Moderne Pixel-Art statt Retro-Look:** Pixel-Stil bleibt, wirkt aber wie heute gemacht: dynamisches Licht, Bloom, weiche Schatten, Unschärfe hinter Menüs, Partikel, Wind in Gras und Stoff, Squash and Stretch, weiche Kamera, klares, animiertes UI. Keine gewollten Grafikfehler, kein „authentisch alt“.
- **Klang:** Chiptune-Wurzeln, aber modern produziert (Bässe, Hall, echte Instrumente gemischt), nicht nur Piepen. OFFEN: ob dafür Komponist oder Werkzeug nötig ist; die synthetischen Skripte (`tools/generate_*.py`) bleiben Platzhalter.
- **Nach außen** sagen wir „moderne Pixel-Art“, nicht „8-Bit“. Website und Store-Seiten beschreiben den Release-Umfang (§5) schon vor dem Release als Teil des Spiels, ohne „kommt“ oder „in Arbeit“; unter „Was kommt“ steht nur, was nach dem Release kommt (D-179).

## 4. Maskottchen (D-175)

- **Wick**, ein kleines Docht-Wesen (eine lebende Kerze mit Flamme), ist das Gesicht von Soulwick (wie die Crewmates bei Among Us). Im Spiel ist Wick dein **persönlicher Begleiter von Anfang an**, Grundlage für Begleiter und Pets; er gehört zum Release-Umfang (§5).
- **Das Huhn** ist Neben-Maskottchen (wie das Schwein bei Minecraft) und taucht immer wieder mit Wick auf.
- Kosmetik gibt es für Spielfigur, Wick und Dorf.
- OFFEN: Name endgültig, Aussehen im Einzelnen (Briefing für Claude Design; eine etwas schlankere Kerze ist erlaubt, wenn Wick so sympathisch bleibt, lieber etwas höher als schmaler, damit er nicht wie ein Quadrat wirkt), was Wick spielerisch tut (Vorschlag: Wick ist die Quelle deines Lichtkreises).

## 5. Spielidee

1. **Endloser Abstieg:** Räume im Fünferzyklus, alle 15 Räume ein Boss, dann Lagerfeuer und neues Biom, der Dungeon endet nie (D-073). Jeder Raum hat eine Aufgabe: Kampf, Arena oder Minispiel (D-120).
2. **Direkte Steuerung:** präzise, sofort verständlich; Maus und Tastatur, Touch (D-168), Gamepad.
3. **Run-Entscheidungen:** Waffen, Upgrades, Spezialräume, Abzweigungen; Gold ist eine Entscheidung (Portal 100 %, Tod 50 %).
4. **Dorf:** ausbauen (Meta-Progression), verschönern (Kosmetik und Deko) und Freunde einladen: gemeinsam im Koop oder als Besuch, auch wenn du nicht da bist (Dorf besuchen).
5. **Zusammen:** Koop für 2 bis 4 Spieler, Einladen per Link oder Raumcode über den eigenen Relay (D-119), Gilden, Ranglisten.

**Modi:**

| Modus | Wann |
| --- | --- |
| Abstieg (endlos, allein oder im Koop mit Freunden) | Kern, zum Release |
| KI-Bosse („Wünsch dir einen Boss“, der Traumweber baut ihn: [KONZEPT_KI_BOSS.md](KONZEPT_KI_BOSS.md)) | zum Release (D-179); stärkster Clip-Moment |
| Party-Modus (nur Minispiele, Spieler gegeneinander, gleiche Grafik) | nach dem Release (D-179) |

**Release-Umfang (D-179):**

| Zum Release im Spiel | Nach dem Release („Was kommt“) |
| --- | --- |
| Koop mit Freunden (Einladen per Link, Gilden, Ranglisten), KI-Bosse, Wick als Begleiter, Dorf ausbauen und verschönern sowie Outfits zum Freispielen (Lesart, D-179), Freunde ins Dorf einladen (Dorf besuchen); spielbar im Browser, auf Steam, Android und iOS (§6) | Party-Modus, laufend neue Minispiele, Bosse und Modi |

- **Release** auf allen Versionen gleichzeitig: Browser, Steam, Android und iOS (D-179; ersetzt die Reihenfolge Steam → Android → iOS aus D-119), erst wenn das Release-Tor in [ROADMAP.md](ROADMAP.md) erfüllt ist.
- **Öffentlich erst ab Release:** Die Social-Media-Phase beginnt mit dem Release (D-179; ob die Steam-Seite „Demnächst verfügbar“ schon dazu zählt, ist OFFEN). Die Website darf vorher online sein; sie beschreibt den Release-Umfang wie vorhanden und schaltet nur Live-Funktionen ab (Spielen und Installieren zeigen „zum Release“, keine Ranglisten- und Gildenseiten). Social-Media-Links erscheinen nur, wenn es den Kanal gibt. Store-Knöpfe sind vor dem Release eigene Pixel-Knöpfe ohne fremde Logos; offizielle Badges kommen erst mit echten Store-Links (D-179, [STORES.md](STORES.md) §6).
- **Echte Personen als KI-Boss:** OFFEN (D-179, Team und Fachanwalt; Risiken in [KONZEPT_KI_BOSS.md](KONZEPT_KI_BOSS.md) §9); bis dahin sind alle Beispiele für Wunschbosse in Doku, Website und Store erfunden.

## 6. Plattformen und Geschäftsmodell (D-176)

Zum Release ist Soulwick auf allen Versionen spielbar – Browser, Steam, Android und iOS – mit Crossplay über alle (D-108, D-179); die frühere Reihenfolge Steam → Android → iOS (D-119) gilt nicht mehr. Das Geschäftsmodell ist eine Arbeitsentscheidung, damit gebaut werden kann; Preise und Termine bleiben OFFEN:

| Wo | Zum Release | Preis | Geld durch |
| --- | --- | --- | --- |
| **Browser** (Web-App) | spielbar (D-148) | kostenlos, ohne Konto, sofort per Link mit Freunden | später Kosmetik; keine Werbung, solange es geht |
| **Handy**: **Android** (Google Play) und **iOS** (App Store, iPhone und iPad) | spielbar | kostenlos | Werbung (freiwillige Belohnungsvideos, ruhige Banner zwischen Runs), „Werbefrei“ als Einmalkauf, Kosmetik |
| **Steam** (PC) | spielbar | kleiner Preis (Größenordnung 3 bis 5 €, OFFEN) | Kaufpreis, Kosmetik; ohne Werbung, Start-Kosmetik inklusive, Steam-Freunde und -Erfolge |

- **Vor dem Release** braucht es dafür alle Store-Konten, auch das Apple Developer Program (iOS und eine notarisierte macOS-Version); Schritte in [STORES.md](STORES.md).

- **Kein Pay-to-win:** Verkauft werden nur Kosmetik und Werbefreiheit, kein Gold, keine Kristalle, keine Stärke. **Keine Lootboxen**, nur direkt kaufbare Gegenstände.
- **Nicht jetzt:** bezahlte Web-App (Hürde widerspricht „schnell reinrennen“), Windows Store (später möglich, dann wie Steam).
- **Später:** Lizenzen, Merch, Plattform-Deals. Die Geschäftsplanung läuft außerhalb des Repos; hier steht nur, was das Produkt betrifft.

## 7. Open Source (D-177)

- **Code** beider Repositories ist öffentlich unter **GPL-3.0**. **Grafik, Musik, Klang, Logo, der Name „Soulwick“ und die Figuren (Wick, Huhn)** sind davon ausgenommen: alle Rechte vorbehalten ([LICENSE-ASSETS.md](../LICENSE-ASSETS.md)).
- **Offizielle Server** sind für alle offen, weil Browser und Handy kostenlos sind. Geschützt wird nicht der Zugang, sondern das Gekaufte: Kosmetik und Werbefreiheit liegen am Konto auf dem Server und werden über die Quittungen der Stores bzw. das Steam-Ticket geprüft (Steam Web API). Ein selbst gebautes Spiel kann lokal alles freischalten, online aber nichts Gekauftes vortäuschen.
- Missbrauch online behandeln Plausibilitätsprüfung, Sperren und Moderation wie bei allen Spielern.

## 8. Online (optional)

Das Spiel bleibt ohne Server spielbar; jeder Aufruf darf scheitern (D-083, D-093). Online kommen dazu: ein Konto mit vielen Anmeldungen (still als Gast, dazu Steam, Play Games, Game Center, Benutzername, Magic Link, Google, Apple, Discord; D-121, D-122, D-188), Welten in der Cloud und ein Konto-Level (D-188), Relay mit Raumcodes (D-119), Gilden (D-147), Run-Berichte und Ranglisten (D-082), Website und Admin-Panel. Gespeichert werden Anmelde-IDs (E-Mail nur, wenn der Spieler sie für die Anmeldung nutzt), Name, Gilde, Run-Berichte, Cloud-Welten und XP. Details: [`soulwick-platform/docs/PRD.md`](https://github.com/WebBude-de/soulwick-platform/blob/main/docs/PRD.md).

## 9. Wo was steht

- Doku-Inhaltsverzeichnis: [README.md](README.md); Arbeitsweise mit Agenten: [AGENTS.md](../AGENTS.md).
- Produkt-Entscheidungen (D-Nummern): [DECISIONS.md](DECISIONS.md); Technik der Plattform (P-Nummern): [`soulwick-platform/docs/DECISIONS.md`](https://github.com/WebBude-de/soulwick-platform/blob/main/docs/DECISIONS.md).
- Bei Widerspruch zwischen den Repos gilt für Produktfragen das Spiel-Repo; für die API gelten die Verträge in `soulwick-platform/packages/contracts`.
