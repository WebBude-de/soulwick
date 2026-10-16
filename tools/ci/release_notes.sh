#!/usr/bin/env bash
# Writes the GitHub release notes (release.yml, docs/RELEASE.md): short install guide per system
# plus the commits since the previous tag. Needs a checkout with history (fetch-depth: 0) and tags.
#
#   TAG=v0.9.1 VERSION=0.9.1 ENVIRONMENT=development PRERELEASE=true ANDROID_TEST_SIGNED=false \
#     tools/ci/release_notes.sh notes.md
#
# Previous tag: for a full release the last full release tag (no suffix), for a pre-release the
# last tag of any kind. Without a previous tag all commits are listed (at most MAX_COMMITS).
# German quotes („…“) in the notes are intended.
# shellcheck disable=SC1111
set -euo pipefail

OUT="${1:?usage: release_notes.sh <notes file>}"
TAG="${TAG:?TAG missing}"
VERSION="${VERSION:?VERSION missing}"
ENVIRONMENT="${ENVIRONMENT:-development}"
PRERELEASE="${PRERELEASE:-true}"
ANDROID_TEST_SIGNED="${ANDROID_TEST_SIGNED:-false}"
# true when the Windows exe is signed / the macOS app notarized (release.yml, docs/STORES.md).
WINDOWS_SIGNED="${WINDOWS_SIGNED:-false}"
MACOS_NOTARIZED="${MACOS_NOTARIZED:-false}"
REPO_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-WebBude-de/soulwick}"
MAX_COMMITS="${MAX_COMMITS:-150}"
name="Soulwick-$VERSION-$ENVIRONMENT"
# Browser version (Dokploy, D-148): the test address for development; production gets a link only
# once the repository variable WEB_PLAY_URL is set (release of the browser version is still open).
if [ "$ENVIRONMENT" = "development" ]; then
	WEB_URL="https://game-dev.playsoulwick.com"
else
	WEB_URL="${WEB_PLAY_URL:-}"
fi

previous=""
while IFS= read -r candidate; do
	[ -n "$candidate" ] || continue
	[ "$candidate" = "$TAG" ] && continue
	if [ "$PRERELEASE" != "true" ] && [ "$candidate" != "${candidate%%-*}" ]; then
		continue
	fi
	previous="$candidate"
	break
done < <(git tag --merged HEAD --sort=-creatordate --list 'v*')

if [ -n "$previous" ]; then
	range="$previous..HEAD"
else
	range="HEAD"
fi
commit_count="$(git rev-list --no-merges --count "$range")"

{
	if [ "$ENVIRONMENT" = "development" ]; then
		echo "> **Testversion** – spielt online mit den Test-Servern. Spielstände und Ranglisten dort können zurückgesetzt werden."
	else
		echo "> Spielt online mit den offiziellen Servern."
	fi
	if [ "$ANDROID_TEST_SIGNED" = "true" ]; then
		echo ">"
		echo "> **Android nur zum Testen:** Die APK ist mit einem Test-Schlüssel signiert. Ist schon eine andere Soulwick-APK installiert, diese erst deinstallieren (der Spielstand auf dem Handy geht dabei verloren)."
	fi
	if [ -n "$WEB_URL" ]; then
		echo
		echo "**Ohne Download im Browser spielen:** $WEB_URL"
	fi
	echo
	echo "## Download"
	echo
	echo "| System | Datei | So geht's |"
	echo "| --- | --- | --- |"
	if [ "$WINDOWS_SIGNED" = "true" ]; then
		echo "| Windows 10/11 | \`$name-windows.zip\` | Entpacken, \`Soulwick.exe\` starten (signiert von WebBude). Warnt SmartScreen trotzdem (neue Signaturen brauchen etwas Zeit): **Weitere Informationen → Trotzdem ausführen**. |"
	else
		echo "| Windows 10/11 | \`$name-windows.zip\` | Entpacken, \`Soulwick.exe\` starten. Warnt Windows SmartScreen („Unbekannter Herausgeber“): **Weitere Informationen → Trotzdem ausführen** (das Spiel ist nicht signiert). |"
	fi
	echo "| Linux (x86_64) | \`$name-linux.zip\` | Entpacken, \`./Soulwick.x86_64\` starten (falls nötig vorher \`chmod +x Soulwick.x86_64\`). |"
	if [ "$MACOS_NOTARIZED" = "true" ]; then
		echo "| macOS (Intel und Apple Silicon) | \`$name-macos.zip\` | Entpacken, \`Soulwick.app\` nach *Programme* ziehen und starten (von Apple beglaubigt). |"
	else
		echo "| macOS (Intel und Apple Silicon) | \`$name-macos.zip\` | Entpacken, \`Soulwick.app\` nach *Programme* ziehen. Das Spiel ist nicht von Apple beglaubigt: beim ersten Start **Rechtsklick → Öffnen**; ab macOS 15 stattdessen *Systemeinstellungen → Datenschutz & Sicherheit → Trotzdem öffnen*. |"
	fi
	echo "| Android 7+ | \`$name-android.apk\` | APK aufs Handy laden und antippen. Fragt Android nach **Installation aus unbekannten Quellen**, für die App, die die Datei öffnet (Dateien, Chrome …), „Dieser Quelle vertrauen“ einschalten. Warnt Play Protect: **Trotzdem installieren**. Updates einfach drüber installieren. |"
	echo
	echo "Zusammen spielen: im Hauptmenü **Online spielen** (oder im Dorf das Gildengebäude), Raum erstellen und den Raumcode an Freunde schicken. PC, Mac und Handy spielen zusammen, wenn alle diese Version haben."
	echo
	echo "*English: unzip and start Soulwick (Windows: SmartScreen → More info → Run anyway; macOS: right-click → Open). Android: allow installing from unknown sources for the app that opens the APK.*"
	echo
	if [ -n "$previous" ]; then
		echo "## Änderungen seit $previous"
	else
		echo "## Änderungen"
	fi
	echo
	git log --no-merges --pretty='- %s (%h)' -n "$MAX_COMMITS" "$range"
	if [ "$commit_count" -gt "$MAX_COMMITS" ]; then
		echo "- … und $((commit_count - MAX_COMMITS)) weitere"
	fi
	if [ -n "$previous" ]; then
		echo
		echo "**Alle Änderungen:** $REPO_URL/compare/$previous...$TAG"
	fi
} > "$OUT"

echo "Release notes: $commit_count commits since ${previous:-the beginning} -> $OUT" >&2
