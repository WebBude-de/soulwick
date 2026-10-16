Soulwick {version} ({env}) - Testversion fuer Freunde / test build for friends
==========================================================================

STARTEN
  Windows: ZIP entpacken, Soulwick.exe doppelklicken. Windows SmartScreen warnt
           ("Unbekannter Herausgeber", der Build ist nicht signiert): "Weitere
           Informationen" -> "Trotzdem ausfuehren".
  Linux:   ZIP entpacken, "chmod +x Soulwick.x86_64", dann ./Soulwick.x86_64
  macOS:   ZIP entpacken, Soulwick.app in "Programme" ziehen. Der Build ist nicht von
           Apple beglaubigt: beim ersten Start Rechtsklick -> "Oeffnen" -> "Oeffnen"
           (oder im Terminal: xattr -cr /Applications/Soulwick.app).
  Browser: ohne Download ueber https://playsoulwick.com spielen (Knopf "Im Browser spielen").

ONLINE (Koop ueber Raumcode)
  Kein Konto, kein Schluessel noetig: Beim ersten Online-Spiel bekommt dieser PC
  automatisch ein Gastkonto. Es haengt an dieser Installation; Spielstand und
  Gastkonto liegen unter %APPDATA%\Godot\app_userdata\Soulwick (nicht loeschen).

  Dann: beim ersten Start Name und Figur waehlen (gilt auch online), im Dorf ins
  Gildengebaeude.
  Host: "Raum erstellen" und den 6-stelligen Raumcode an die anderen schicken.
  Alle anderen: Raumcode eingeben, "Raum beitreten". Host drueckt "Starten".
  Keine Portfreigabe, kein VPN, keine Zusatzsoftware.

  Unten rechts im Hauptmenue stehen Version und Online-Status. "Bitte aktualisiere das
  Spiel" heisst: neue Version holen; Einzelspieler geht trotzdem.

RUECKMELDUNG
  Lag, Abbrueche (mit Uhrzeit), Fehler, Schwierigkeit, Spass. Logdatei:
  Windows %APPDATA%\Godot\app_userdata\Soulwick\logs\godot.log
  Linux   ~/.local/share/godot/app_userdata/Soulwick/logs/godot.log
  macOS   ~/Library/Application Support/Godot/app_userdata/Soulwick/logs/godot.log
