# Contributing to Soulwick

Thanks for wanting to help! Bug reports, ideas and pull requests are all welcome. **English or German
is fine** – the project docs are in German ([docs/README.md](docs/README.md)), the code is in English.

## Ways to help

- **Report a bug:** in a test build press **Ctrl + B** (**Cmd + B** on a Mac), **F9** or **#**, press
  Back + Start together on a gamepad or tap the bug button on your phone – the report gets a
  screenshot and game info automatically. Or use the
  [bug report form](https://github.com/WebBude-de/soulwick/issues/new/choose).
- **Share an idea:** a mini-game, a boss, a weapon, something for the village – open an idea issue.
- **Write code:** pick an issue (look for `good first issue` and `help wanted`) or open one first for
  bigger changes, so we can agree on the direction before you spend time on it.
- Website, API, relay and admin panel live in
  [soulwick-platform](https://github.com/WebBude-de/soulwick-platform).

## Set up

Godot 4.7.2 stable, standard version, and Git LFS – see [Build from source](README.md#build-from-source).

## Branches and commits

- `main` holds stable releases, `dev` is where work comes together; nobody pushes to them directly –
  everything goes through a pull request.
- Branch off `dev`: `feature/<topic>` for features, `fix/<topic>` for fixes; open the pull request
  against `dev`. Urgent release fixes: `hotfix/<topic>` against `main`, then back into `dev`.
- Every pull request needs **one review** by someone else and a green CI.
- Commit messages: `type(scope): summary` in English, for example `feat(player): add dash movement` or
  `fix(dungeon): prevent duplicate enemy spawns`. Types: `feat`, `fix`, `refactor`, `docs`, `test`,
  `chore`. Details: [docs/TECHSTACK.md](docs/TECHSTACK.md) §3.

## Conventions

- **Code and comments in English, docs in German, in-game text through translation keys** in
  `localization/` (English and German, see [localization/README.md](localization/README.md)).
- `snake_case` for files and variables, `PascalCase` for classes; exactly Godot 4.7.2.
- Exactly four autoloads (GameManager, RunManager, SaveManager, EventBus) – helpers are
  `static func` / `class_name`, not new autoloads.
- Keep co-op in mind: no new `get_first_node_in_group(&"player")`, randomness only through the
  dungeon RNG, state per player on the player ([AGENTS.md](AGENTS.md) §6).
- Tests and tools never touch the real save file: point `SaveManager.save_path` at a test file first.
- Product decisions are documented in [docs/DECISIONS.md](docs/DECISIONS.md) as D-numbers. Do not
  silently decide anything marked `OFFEN` (open) – ask in the issue or pull request instead.

## Before you open a pull request

```bash
godot --headless --audio-driver Dummy --path . -s tools/validate_project.gd
godot --headless --audio-driver Dummy --path . -s addons/gut/gut_cmdln.gd -gexit
```

Changes to combat and enemies: also `tools/combat_sim.gd` and `tools/boss_sim.gd`; changes to rooms:
`tools/smoke_test.gd` ([AGENTS.md](AGENTS.md) §7). Always run Godot from scripts with
`--audio-driver Dummy`.

## Artwork, music and sound

The content of Soulwick (artwork, music, sound, logo, name, characters) is **not** open source
([LICENSE-ASSETS.md](LICENSE-ASSETS.md)). Please **do not send artwork, music or sound without
talking to us first** – open an issue and we will figure it out together. Placeholders drawn by code
are fine. If a feature needs new art, describe it as a briefing (see
[docs/design/sprites/README.md](docs/design/sprites/README.md)).

## Working with AI assistants

AI-assisted contributions are welcome. This repository is set up for coding agents: read
[AGENTS.md](AGENTS.md) (German) – it holds the rules for agents (ownership of files, checks, no
commits without approval). You are responsible for what you submit: understand it, test it, keep the
diff focused.

## License of contributions

By submitting a contribution you agree that it is licensed under the
**GNU General Public License v3.0 or later**, the license of the code ("inbound = outbound"), and that
you have the right to contribute it. Whether we will ask for a contributor license agreement (CLA)
later is still open; we will say so here before it applies to anyone.

## Code of Conduct and security

Be kind – we follow the [Code of Conduct](CODE_OF_CONDUCT.md). Security problems go through
[SECURITY.md](SECURITY.md), never a public issue.
