Soulwick {version} ({env}) - Testversion fuer Freunde / test build for friends
==========================================================================

STARTEN
  Windows: ZIP entpacken, Soulwick.exe doppelklicken. Windows SmartScreen warnt
           ("Unbekannter Herausgeber", der Build ist nicht signiert): "Weitere
           Informationen" -> "Trotzdem ausfuehren".
  Linux:   ZIP entpacken, "chmod +x Soulwick.x86_64", dann ./Soulwick.x86_64

ONLINE (Koop ueber Raumcode)
  Der Dev-Schluessel steckt NICHT im Build. Du bekommst ihn privat vom Projektteam.
  Einmal eintragen, dann gilt er fuer jeden Start:

  Windows (PowerShell, <KEY> ersetzen):
    $d = "$env:APPDATA\Godot\app_userdata\Soulwick"; New-Item -ItemType Directory -Force $d | Out-Null
    Set-Content "$d\online.cfg" "[settings]`ndev_key=`"<KEY>`""

  Linux:
    mkdir -p ~/.local/share/godot/app_userdata/Soulwick
    printf '[settings]\ndev_key="<KEY>"\n' > ~/.local/share/godot/app_userdata/Soulwick/online.cfg

  Oder nur fuer einen Start:  Soulwick.exe -- dev_key=<KEY>

  Dann: Spielstand anlegen (der Name wird dein Online-Name), im Dorf ins Gildengebaeude.
  Host: "Raum erstellen" und den 6-stelligen Raumcode an die anderen schicken.
  Alle anderen: Raumcode eingeben, "Raum beitreten". Host drueckt "Starten".
  Keine Portfreigabe, kein VPN, keine Zusatzsoftware.

  Unten rechts im Hauptmenue stehen Version und Online-Status. "Bitte aktualisiere das
  Spiel" heisst: neue Version holen; Einzelspieler geht trotzdem.

RUECKMELDUNG
  Lag, Abbrueche (mit Uhrzeit), Fehler, Schwierigkeit, Spass. Logdatei:
  Windows %APPDATA%\Godot\app_userdata\Soulwick\logs\godot.log
  Linux   ~/.local/share/godot/app_userdata/Soulwick/logs/godot.log
