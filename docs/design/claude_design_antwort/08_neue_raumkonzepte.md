# Neue Raumkonzepte (Seite 2)

Seite 2: weitere Raumkonzepte über KONZEPT_RAEUME_V2 hinaus. Jedes in einem Satz erklärbar, 20–60 s, Koop-fähig, mit Vorlagen baubar. Sortiert nach Aufwand (S/M/L). Empfehlung: zuerst Hühnerhof, Wachsrennen, Flut und Grabräuber testen (kleinster Bau, größter Kontrast zu den vorhandenen Modi).

## Hühnerhof · Minispiel · Hüten · Aufwand S

„Treib die fünf Hühner in den Stall, bevor die Schleime sie fressen.“

- **Twist:** Hühner fliehen vor dir und vor Gegnern; du treibst, indem du dich hinter sie stellst. Koop: zwei treiben, zwei verteidigen. Humor + Herding, nichts im Spiel ist ähnlich.
- **Bau:** Kleiner Hof mit Zaunresten, Stall als Nische in der Nordwand mit offener Klappe; Hühner starten verstreut.
- **Quelle:** Pfützen am Rand.
- **Belohnung:** Gold je Huhn, alle fünf = Truhe. Gerettete Hühner laufen im Dorf herum.
- **Tür:** Huhn-Symbol, warmes Licht.
- **Sprites:** chicken_panic_4f, hen_house.png (48×48), fence_broken.png

## Wachsrennen · Minispiel · Rennen · Aufwand S

„Erreiche den Ausgang, bevor deine Kerze abbrennt.“

- **Twist:** Dein Lichtkreis schrumpft stetig (Kerze); Abkürzungen führen durch Fallen, Umwege sind sicher. Gegner nur als Hindernis. Koop: nur eine Kerze, die Gruppe muss zusammenbleiben.
- **Bau:** Langer Raum (25×11) mit drei Routen: Spießrute kurz, Brücke mittel, Umweg lang. Ziel-Tor oben rechts.
- **Quelle:** keine (reines Rennen) oder Vents, die den Umweg nach 20 s schließen.
- **Belohnung:** Rest-Kerzenlänge = Gold; unter 15 s Kristall.
- **Tür:** Kerzen-Symbol, gelb, flackert.
- **Sprites:** candle_hud_6f, candle_stub.png

## Dunkle Flut · Minispiel · Überleben · Aufwand M

„Der Schleim steigt – halte dich oben, bis er abfließt.“

- **Twist:** Von Süden füllt sich der Raum mit Schleim (verlangsamt + Schaden); Podeste (Innenmauer-Kronen als begehbare Erhöhung) sind sicher, Gegner spawnen aus der Flut. Nach 30 s fließt alles ab und legt die Truhe frei.
- **Bau:** Treppenartiger Grundriss: drei Ebenen aus 2-Kachel-Podesten, Abfluss unten.
- **Quelle:** Flut selbst (Pfützen-Quelle überall im Schleim).
- **Belohnung:** Truhe im Abfluss, Kristall wenn nie berührt.
- **Tür:** Wellen-Symbol, grün.
- **Sprites:** flood_tile_4f (32×32 Overlay), flood_edge_4f, drain_grate.png

## Grabräuber · Minispiel · Risiko · Aufwand M

„Grab die Gräber aus – jedes weckt mehr Tote. Hör auf, wann du willst.“

- **Twist:** Press-your-luck: jedes ausgegrabene Grab gibt Gold/Loot, aber jedes dritte weckt einen Mumien-Schub. Der Spieler entscheidet, wann er zur Tür geht (Tür ist offen!). Koop: Streit um ein Grab mehr.
- **Bau:** Friedhof: 8 Gräber in zwei Bögen, Mausoleum als Deckung, Tür immer offen.
- **Quelle:** Gräber (spawn_grave).
- **Belohnung:** Gold progressiv, 8/8 = Upgrade.
- **Tür:** Schaufel-Symbol, grün-gold.
- **Sprites:** grave_dug_3f, shovel_icon, mummy_idle/walk/attack/death (32×32)

## Glockenspiel · Minispiel · Merken · Aufwand M

„Schlag die Glocken in der Reihenfolge, die der Raum vorgibt.“

- **Twist:** Vier Glocken leuchten nacheinander auf (Simon), du schlägst sie mit der Waffe nach; falsche Glocke ruft Gegner. Drei Runden, jede länger. Koop: jeder steht an einer Glocke.
- **Bau:** Kreuzraum, eine Glocke je Arm, Mitte frei.
- **Quelle:** Risse unter den Glocken bei Fehlern.
- **Belohnung:** Truhe; fehlerfrei = Kristall.
- **Tür:** Glocken-Symbol, gold.
- **Sprites:** bell_4f (32×48), bell_glow_4f

## Fährmann · Minispiel · Balance · Aufwand L

„Steh auf dem Floß und wehr ab, was aufspringt, bis es anlegt.“

- **Twist:** Ein Floß treibt 40 s über den Abgrund; wo die Spieler stehen, kippt es (Bewegung = Steuerung). Gegner springen von Inseln auf. Nutzt den Abgrund als Bauteil.
- **Bau:** Abgrund-Kanal mit Inseln links und rechts, Floß 3×2 Kacheln, Anleger am Ziel.
- **Quelle:** Schattenrisse auf den Inseln.
- **Belohnung:** Truhe am Anleger.
- **Tür:** Ruder-Symbol, blau.
- **Sprites:** raft_96x64_4f, raft_tilt_4f, mooring_post

## Kerkermeister · Minispiel · Rettung · Aufwand L

„Befreie die drei Gefangenen – der Schlüsselträger flieht.“

- **Twist:** Mischung aus Jagd und Geleit: ein Wärter rennt mit dem Schlüsselbund weg, drei Käfige stehen im Raum; Befreite helfen (werfen Steine). Koop: Gefangene = Mitspieler (vgl. §3.11 Rettung).
- **Bau:** Kerkergang mit Zellen als Nischen in der Nordwand, Wärterloge als Innenmauer.
- **Quelle:** Zellen (Türen öffnen, Gegner statt Gefangene in 1 von 4).
- **Belohnung:** Gerettete im Dorf, Truhe.
- **Tür:** Schlüssel-Symbol, orange.
- **Sprites:** cage_32x48_closed/open, warden_idle/run (32×32), keyring_icon

## Brutkammer · Kampf-Variante · Elite · Aufwand S

„Zerstöre die Eier, bevor sie schlüpfen.“

- **Twist:** Elite-Nest mit Timer: 6 Eier pulsieren, jedes schlüpft nach 20–40 s zu einem Elite-Gegner. Je mehr du vorher zerstörst, desto leichter. Reine Priorisierung.
- **Bau:** Grotten-Höhle mit Eiern in Mulden, Schleimfäden an den Wänden.
- **Quelle:** Eier.
- **Belohnung:** Kristalle je zerstörtem Ei.
- **Tür:** Ei-Symbol, violett.
- **Sprites:** egg_pulse_4f (32×32), egg_hatch_4f, slime_strands

## Bibliothek der Flüsterer · Ruhe-Raum · Aufwand S

„Lies ein Blatt und wähle einen Segen für drei Räume.“

- **Twist:** Kurze Lore (eine Zeile je Biom) plus ein zeitlich begrenzter Buff (z. B. +1 Herz-Schild für 3 Räume). Gibt dem Dungeon Stimme ohne Dialogsystem.
- **Bau:** Kleiner Raum mit Regalen (Nischen), Lesepult in der Mitte, Kerzen.
- **Quelle:** keine.
- **Belohnung:** Segen.
- **Tür:** Buch-Symbol, blau.
- **Sprites:** lectern.png (32×40), bookshelf_niche (32×48), blessing_icons (6×16×16)

## Kartentisch · Ruhe-Raum · Agency · Aufwand M

„Sieh die nächsten fünf Räume und tausche zwei.“

- **Twist:** Zeigt den Zyklus als Karte mit Symbolen; der Spieler darf zwei Plätze tauschen (z. B. Arena vor den Ruheraum). Gibt Planung und macht die Symbole lernbar.
- **Bau:** Kleiner Raum mit Kartentisch, Kerzen, Karte als UI.
- **Quelle:** keine.
- **Belohnung:** Information, Kontrolle.
- **Tür:** Karten-Symbol, grau.
- **Sprites:** map_table.png (64×32), route_card_ui

## Schrein der Gefallenen · Geheimnis · Meta · Aufwand S

„Dein letzter Run liegt hier – nimm, was er trug.“

- **Twist:** Zeigt eine Statue/Geist an der Stelle des letzten Todes (Raumnummer passend); Interaktion gibt einen Teil des verlorenen Run-Golds zurück. Koop: Geister aller Mitspieler.
- **Bau:** Nische hinter rissiger Wand oder Lagerfeuer-Zusatz.
- **Quelle:** keine.
- **Belohnung:** 25 % des verlorenen Golds, einmal.
- **Tür:** kein eigener Raum.
- **Sprites:** ghost_player_idle_4f (halbtransparente Spielerkopie per Shader), shrine_small

## Zugbrücke · Minispiel · Halten · Aufwand M

„Dreh die Winde, bis die Brücke unten ist – lass nicht los.“

- **Twist:** E halten dreht die Winde (Fortschritt 0–100 %), Loslassen lässt sie zurückrollen; Gegner kommen von hinten. Koop: einer kurbelt, die anderen decken (Rollenwechsel durch Ablösen).
- **Bau:** Abgrund trennt Eingang und Ausgang; Winde am Rand, Brücke senkt sich sichtbar.
- **Quelle:** Vents hinter dem Spieler.
- **Belohnung:** Truhe hinter der Brücke.
- **Tür:** Winden-Symbol, braun.
- **Sprites:** winch_4f (32×32), drawbridge_8f (96×32)

## Koop

Aus §3.11 passend zu diesen Räumen: Doppelgänger im Hühnerhof (ein Spieler sieht für die anderen wie ein Fuchs aus), Staffel in der Zugbrücke (Kurbel muss durch alle Hände), Geteiltes Licht im Wachsrennen.
