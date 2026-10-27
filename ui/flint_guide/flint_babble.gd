class_name FlintBabble
extends RefCounted
## Flint's babble while he explains (D-098: readable text, babbled voice). One short sound per
## syllable through the usual UI sound path (Sfx.play_ui, bus SFX). Flint's own syllables
## audio/sfx/babble_flint_<1..6>.wav are used once they exist (tools/generate_audio.py, fx-audio);
## until then the soft typing ticks of the menus (ui_type_<1..4>) babble for him. The same syllable
## always gets the same sound (BossIntroRules.babble_variant, no randomness).

const OWN_PREFIX := "babble_flint_"
const OWN_VARIANTS := 6
const FALLBACK_PREFIX := UiSound.TYPE_PREFIX
const FALLBACK_VARIANTS := UiSound.TYPE_VARIANTS
## Volume in dB (TESTWERT): under the boss voices, over the menu typing.
const VOLUME_DB := -7.0


## The sound for a syllable: Flint's own when it exists, else a typing tick.
static func sound_for(syllable: String) -> StringName:
	if has_own_voice():
		return StringName(OWN_PREFIX + str(BossIntroRules.babble_variant(syllable, OWN_VARIANTS)))
	return StringName(FALLBACK_PREFIX + str(BossIntroRules.babble_variant(syllable, FALLBACK_VARIANTS)))


static func has_own_voice() -> bool:
	return ResourceLoader.exists(Sfx.SFX_DIR + OWN_PREFIX + "1.wav")


static func play(context: Node, syllable: String) -> void:
	Sfx.play_ui(context, sound_for(syllable), VOLUME_DB)
