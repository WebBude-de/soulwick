# Security policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Report them privately through GitHub:

**[Security → Report a vulnerability](https://github.com/WebBude-de/soulwick/security/advisories/new)**

If that does not work for you, write to [hello@playsoulwick.com](mailto:hello@playsoulwick.com) with
"Security" in the subject. English or German is fine.

Helpful details: what is affected, the game version (main menu) and platform, steps to reproduce and
what an attacker could do with it. We are a small team and answer as soon as we can, usually within a
week. We will keep you posted, fix the issue and credit you in the advisory if you like.

## Supported versions

Soulwick is in development. Fixes land in `dev` and ship with the next build.

| Version | Supported |
| --- | --- |
| Newest release or pre-release on [GitHub Releases](https://github.com/WebBude-de/soulwick/releases), browser version at [game.playsoulwick.com](https://game.playsoulwick.com) (from release) | yes |
| `main` and `dev` | yes |
| Older builds | no – please update |

## Scope

This repository covers the game client, its browser build (`deploy/`, `Dockerfile`) and the build and
release pipeline (`.github/`, `tools/ci/`). Problems with the website, the API, the co-op relay or the
admin panel belong to [soulwick-platform](https://github.com/WebBude-de/soulwick-platform/security)
– but if you are unsure, just report it here.

Examples we care about: code execution through save files, network packets or co-op sessions; leaked
tokens or keys; ways to change other players' data, runs or leaderboard entries; anything in the
release pipeline that could ship a tampered build.

Not a vulnerability: changing your own local game. The code is open source, so a self-built game can
unlock anything locally – purchases and online data are checked on the server.

## Player data

The game keeps saves on your device. Online it sends only platform IDs, your name, your guild and run
reports; bug reports from test builds add a screenshot and game info and are deleted after 90 days.
Details: [privacy policy](https://playsoulwick.com/privacy). If you find a way to reach data of other
players, please stop there and report it privately.
