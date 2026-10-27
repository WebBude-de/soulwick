class_name ControlsHint
extends RefCounted
## What is left of the first-run controls card (UX1) since Flint says the keys instead (team member
## 22.10.2026: "Ganz durch Flint ersetzen", FlintControls): the save's flag the HUD's key line
## follows (full until the first run reached room FlintControls.LAST_ROOM, then short), the old
## flags (worlds that saw the card or the overview tip skip Flint's hints for the same keys) and
## the place of the teaching cards on the left edge (enemy hints, RoomIntroCard). All keys stay to
## look up in the pause menu (Optionen, Tasten).

## Save flag: the first-run controls were taught (set by FlintControls, read by Hud).
const SEEN_ID: StringName = &"hint_controls"
## Old save flag of the overview tip in the first upgrade dialog (P1-4); only read now.
const OVERVIEW_TIP_ID: StringName = &"hint_overview_key"


## Top of a teaching card of height on the left edge: below the HUD's status frame, never lower
## than vertically centred.
static func card_top(card: Control, height: float) -> float:
	var view := card.get_viewport_rect().size
	var top := Hud.teaching_card_top(card.get_tree() if card.is_inside_tree() else null)
	return floorf(clampf(top, 0.0, maxf(0.0, (view.y - height) * 0.5)))
