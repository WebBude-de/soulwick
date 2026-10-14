"""Synthesizes all sound effects as WAV files (pure Python, no dependencies).

Usage (from the project root):  python tools/generate_audio.py
Output: audio/sfx/*.wav. Every file can be replaced by a custom file of the same name (D-068).
Music is rendered separately by tools/generate_music.py.
"""
import math
import random
import struct
import wave
from array import array
from pathlib import Path

SR = 22050
ROOT = Path(__file__).resolve().parent.parent
SFX_DIR = ROOT / "audio" / "sfx"
TAU = 2.0 * math.pi


# ---------------------------------------------------------------- basics

def midi(note):
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def wave_value(kind, phase, duty=0.5):
    if kind == "square":
        return 1.0 if phase < duty else -1.0
    if kind == "triangle":
        return 4.0 * phase - 1.0 if phase < 0.5 else 3.0 - 4.0 * phase
    if kind == "saw":
        return 2.0 * phase - 1.0
    if kind == "sine":
        return math.sin(TAU * phase)
    return random.uniform(-1.0, 1.0)


def envelope(i, n, attack, release, decay_to=1.0):
    t = i / SR
    total = n / SR
    a = min(1.0, t / attack) if attack > 0 else 1.0
    d = 1.0 + (decay_to - 1.0) * (i / n)
    r = min(1.0, (total - t) / release) if release > 0 else 1.0
    return a * d * max(0.0, r)


def tone(freq, dur, kind="square", vol=0.5, duty=0.5, slide_to=None, attack=0.004, release=0.04,
         decay_to=1.0, vibrato_rate=0.0, vibrato_depth=0.0):
    n = max(1, int(dur * SR))
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        f = freq
        if slide_to is not None:
            f = freq * (slide_to / freq) ** (i / n)
        if vibrato_depth:
            f *= 1.0 + vibrato_depth * math.sin(TAU * vibrato_rate * i / SR)
        phase = (phase + f / SR) % 1.0
        out[i] = wave_value(kind, phase, duty) * vol * envelope(i, n, attack, release, decay_to)
    return out


def noise(dur, vol=0.5, cutoff=1.0, attack=0.002, release=0.05, decay_to=1.0, cutoff_to=None):
    """Filtered noise; cutoff in 0..1 (one-pole low-pass coefficient)."""
    n = max(1, int(dur * SR))
    out = [0.0] * n
    last = 0.0
    for i in range(n):
        c = cutoff if cutoff_to is None else cutoff + (cutoff_to - cutoff) * i / n
        last += c * (random.uniform(-1.0, 1.0) - last)
        out[i] = last * vol * envelope(i, n, attack, release, decay_to)
    return out


def mix(*parts, offsets=None):
    offsets = offsets or [0.0] * len(parts)
    length = max(int(o * SR) + len(p) for p, o in zip(parts, offsets))
    out = [0.0] * length
    for part, offset in zip(parts, offsets):
        start = int(offset * SR)
        for i, v in enumerate(part):
            out[start + i] += v
    return out


def seq(*parts, gap=0.0):
    out = []
    for part in parts:
        out.extend(part)
        out.extend([0.0] * int(gap * SR))
    return out


def write_wav(path, samples, peak=0.85):
    path.parent.mkdir(parents=True, exist_ok=True)
    top = max(1e-9, max(abs(v) for v in samples))
    scale = peak / top
    data = array("h", (int(max(-1.0, min(1.0, v * scale)) * 32767) for v in samples))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


# ---------------------------------------------------------------- sound effects

def build_sfx():
    random.seed(1)
    fx = {}
    fx["sword_swing"] = mix(noise(0.16, 0.6, 0.35, release=0.1, cutoff_to=0.08),
                            tone(900, 0.12, "sine", 0.15, slide_to=300, release=0.08))
    fx["bow_shot"] = mix(tone(520, 0.1, "square", 0.35, duty=0.25, slide_to=260, release=0.06),
                         noise(0.05, 0.4, 0.6, release=0.04))
    fx["staff_cast"] = mix(tone(420, 0.26, "triangle", 0.5, slide_to=980, vibrato_rate=18, vibrato_depth=0.04),
                           tone(840, 0.26, "square", 0.08, duty=0.125, slide_to=1960))
    fx["explosion"] = mix(noise(0.65, 0.9, 0.25, release=0.5, decay_to=0.2, cutoff_to=0.03),
                          tone(90, 0.5, "sine", 0.7, slide_to=35, release=0.3))
    fx["hit_enemy"] = mix(noise(0.07, 0.6, 0.5, release=0.05), tone(240, 0.07, "square", 0.3, duty=0.25, slide_to=140))
    fx["hit_player"] = mix(tone(320, 0.22, "square", 0.45, slide_to=110, release=0.1),
                           noise(0.12, 0.5, 0.3, release=0.1))
    fx["enemy_death"] = mix(tone(380, 0.32, "square", 0.35, duty=0.25, slide_to=70, release=0.12),
                            noise(0.25, 0.35, 0.2, release=0.2, cutoff_to=0.05))
    fx["player_death"] = seq(*[tone(midi(n), 0.2, "square", 0.4, duty=0.5, release=0.08) for n in (64, 60, 57)],
                             tone(midi(52), 0.6, "triangle", 0.6, release=0.4, vibrato_rate=6, vibrato_depth=0.02))
    fx["dash"] = noise(0.16, 0.55, 0.7, release=0.12, cutoff_to=0.15)
    fx["coin"] = seq(tone(988, 0.05, "square", 0.3, duty=0.25), tone(1319, 0.1, "square", 0.3, duty=0.25, release=0.08))
    fx["heal"] = seq(*[tone(midi(n), 0.08, "triangle", 0.5) for n in (72, 76, 79)], tone(midi(84), 0.18, "triangle", 0.5, release=0.12))
    fx["shield"] = tone(880, 0.28, "square", 0.25, duty=0.125, vibrato_rate=30, vibrato_depth=0.06, release=0.15)
    fx["door_open"] = mix(noise(0.45, 0.5, 0.06, release=0.3), tone(140, 0.4, "saw", 0.15, slide_to=95, release=0.2))
    fx["upgrade"] = seq(*[tone(midi(n), 0.07, "square", 0.3, duty=0.25) for n in (67, 71, 74, 79)],
                        mix(tone(midi(83), 0.35, "square", 0.3, duty=0.25, release=0.25), tone(midi(79), 0.35, "triangle", 0.4, release=0.25)))
    fx["ui_click"] = tone(1100, 0.035, "square", 0.25, duty=0.25, release=0.02)
    fx["ui_open"] = mix(tone(500, 0.12, "triangle", 0.4, slide_to=900, release=0.06), noise(0.08, 0.15, 0.5))
    fx["stun"] = seq(*[tone(f, 0.07, "triangle", 0.45) for f in (1400, 1000, 1400, 1000, 1400)])
    fx["blind"] = mix(tone(500, 0.7, "sine", 0.6, slide_to=90, release=0.4, vibrato_rate=9, vibrato_depth=0.05),
                      noise(0.7, 0.3, 0.05, release=0.5))
    fx["trap"] = mix(noise(0.12, 0.7, 0.9, release=0.1), tone(1800, 0.1, "square", 0.15, duty=0.125, slide_to=900))
    fx["crate_break"] = mix(noise(0.3, 0.8, 0.35, release=0.25, decay_to=0.3), tone(180, 0.15, "square", 0.2, slide_to=90))
    fx["boss_roar"] = mix(tone(95, 1.3, "saw", 0.6, slide_to=55, vibrato_rate=7, vibrato_depth=0.08, release=0.5, attack=0.08),
                          noise(1.3, 0.5, 0.08, release=0.6, attack=0.1))
    fx["portal"] = mix(*[tone(midi(n), 0.9, "triangle", 0.25, vibrato_rate=5, vibrato_depth=0.01, release=0.5, attack=0.1)
                         for n in (60, 64, 67, 72)])
    fx["room_clear"] = seq(*[tone(midi(n), 0.09, "square", 0.3, duty=0.5) for n in (72, 76, 79)],
                           mix(tone(midi(84), 0.4, "square", 0.3, duty=0.5, release=0.3), tone(midi(76), 0.4, "triangle", 0.4, release=0.3)))
    fx["fuse"] = tone(1500, 0.06, "square", 0.35, duty=0.5, release=0.02)
    fx["charge"] = mix(tone(200, 0.35, "saw", 0.35, slide_to=480, release=0.1), noise(0.35, 0.25, 0.3))
    fx["slam"] = mix(noise(0.4, 0.9, 0.12, release=0.35), tone(70, 0.35, "sine", 0.9, slide_to=35))
    fx["teleport"] = mix(tone(300, 0.25, "sine", 0.5, slide_to=1600, release=0.1), noise(0.2, 0.2, 0.8, release=0.15))
    fx["enemy_shoot"] = tone(700, 0.08, "square", 0.25, duty=0.25, slide_to=400)
    fx["heart"] = seq(tone(midi(76), 0.06, "triangle", 0.5), tone(midi(83), 0.15, "triangle", 0.5, release=0.1))
    for name, samples in fx.items():
        write_wav(SFX_DIR / f"{name}.wav", samples, peak=0.8)
    return len(fx)


# ---------------------------------------------------------------- boss babble (boss intro)
# Gibberish voices for the boss intro (Animal Crossing / Undertale principle): one short syllable
# sound per spoken syllable, several pitches per boss. Files: babble_<voice>_<n>.wav, n = 1..6.
# The voice ids match EnemyData.intro_voice. All pitches and lengths are TESTWERTE.

BABBLE_VARIANTS = 6
# Semitone offsets of the variants: a small, slightly ominous scale.
BABBLE_STEPS = (0, 3, 5, 6, 10, 12)


def _step(base, i):
    return base * 2.0 ** (BABBLE_STEPS[i] / 12.0)


def babble_bone_king(i):
    """Clattering: two dry clicks (bone on bone) over a hollow, short tone."""
    f = _step(540.0, i)
    click_a = mix(noise(0.022, 0.75, 0.9, release=0.018),
                  tone(f, 0.03, "square", 0.35, duty=0.25, slide_to=f * 0.7, release=0.02))
    click_b = mix(noise(0.018, 0.55, 0.95, release=0.014),
                  tone(f * 1.33, 0.024, "square", 0.25, duty=0.125, slide_to=f, release=0.015))
    hollow = tone(f * 0.42, 0.07, "triangle", 0.35, slide_to=f * 0.33, release=0.04)
    return mix(click_a, click_b, hollow, offsets=[0.0, 0.038, 0.004])


def babble_slime_queen(i):
    """Bubbling: a wobbly sine bloop that rises and ends in a tiny wet pop."""
    f = _step(250.0, i)
    bloop = tone(f, 0.09, "sine", 0.6, slide_to=f * 1.9, vibrato_rate=34, vibrato_depth=0.08,
                 attack=0.01, release=0.03)
    body = tone(f * 0.5, 0.08, "triangle", 0.25, slide_to=f * 0.9, release=0.03)
    pop = noise(0.015, 0.35, 0.5, release=0.012)
    return mix(bloop, body, pop, offsets=[0.0, 0.0, 0.082])


def babble_shadow_lord(i):
    """Hissing and echoing: airy noise with a faint whisper tone, repeated twice like in a hall."""
    f = _step(190.0, i)
    hiss = mix(noise(0.085, 0.6, 0.7, attack=0.012, release=0.05, cutoff_to=0.35),
               tone(f, 0.085, "triangle", 0.22, slide_to=f * 0.8, vibrato_rate=9, vibrato_depth=0.04,
                    attack=0.012, release=0.05))
    echo_a = [v * 0.42 for v in hiss]
    echo_b = [v * 0.18 for v in hiss]
    return mix(hiss, echo_a, echo_b, offsets=[0.0, 0.075, 0.15])


def babble_ember_golem(i):
    """Rumbling deep: a growling saw with fast tremolo, a sub sine and gravel noise."""
    f = _step(68.0, i)
    growl = tone(f, 0.12, "saw", 0.55, slide_to=f * 0.82, vibrato_rate=28, vibrato_depth=0.12,
                 attack=0.012, release=0.05)
    sub = tone(f * 0.5, 0.12, "sine", 0.6, slide_to=f * 0.42, attack=0.01, release=0.05)
    gravel = noise(0.1, 0.3, 0.05, attack=0.01, release=0.06)
    return mix(growl, sub, gravel)


BABBLE_VOICES = {
    "bone_king": babble_bone_king,
    "slime_queen": babble_slime_queen,
    "shadow_lord": babble_shadow_lord,
    "ember_golem": babble_ember_golem,
}


def build_babble():
    # Own seed: the regular sound effects above stay byte-identical.
    random.seed(7)
    count = 0
    for voice, make in BABBLE_VOICES.items():
        for i in range(BABBLE_VARIANTS):
            write_wav(SFX_DIR / f"babble_{voice}_{i + 1}.wav", make(i), peak=0.75)
            count += 1
    return count


# ---------------------------------------------------------------- menu sounds (UX1)
# Quiet, short UI sounds next to ui_click / ui_open: typing, closing, switches, "not possible",
# confirm and delete. Rendered with a lower peak than the effects (dezent). Names: ui/ui_sound.gd.
# All pitches and lengths are TESTWERTE.

UI_TYPE_PITCHES = (1.0, 1.06, 0.95, 1.12)


def ui_type(pitch):
    """One key stroke: a tiny filtered noise tick with a short high body."""
    return mix(noise(0.022, 0.5, 0.75, attack=0.001, release=0.016),
               tone(1650 * pitch, 0.018, "triangle", 0.35, attack=0.001, release=0.012))


def build_ui():
    # Own seed: the regular sound effects and the babble above stay byte-identical.
    random.seed(11)
    ui = {}
    for i, pitch in enumerate(UI_TYPE_PITCHES):
        ui[f"ui_type_{i + 1}"] = ui_type(pitch)
    ui["ui_type_delete"] = mix(noise(0.03, 0.5, 0.45, attack=0.001, release=0.02),
                               tone(980, 0.028, "triangle", 0.35, slide_to=760, attack=0.001, release=0.016))
    ui["ui_back"] = mix(tone(820, 0.09, "triangle", 0.4, slide_to=470, release=0.05), noise(0.05, 0.1, 0.5))
    ui["ui_toggle"] = seq(tone(900, 0.025, "square", 0.22, duty=0.25, release=0.012),
                          tone(1350, 0.035, "square", 0.22, duty=0.25, release=0.02), gap=0.012)
    ui["ui_error"] = seq(tone(196, 0.06, "square", 0.3, duty=0.5, release=0.02),
                         tone(165, 0.09, "square", 0.3, duty=0.5, release=0.05), gap=0.02)
    ui["ui_confirm"] = seq(*[tone(midi(n), 0.05, "triangle", 0.45) for n in (72, 79)],
                           mix(tone(midi(84), 0.22, "triangle", 0.45, release=0.16),
                               tone(midi(91), 0.22, "square", 0.08, duty=0.125, release=0.16)))
    ui["ui_delete"] = mix(noise(0.28, 0.45, 0.25, release=0.2, cutoff_to=0.04),
                          tone(420, 0.24, "triangle", 0.4, slide_to=140, release=0.14))
    for name, samples in ui.items():
        write_wav(SFX_DIR / f"{name}.wav", samples, peak=0.55)
    return len(ui)


# ---------------------------------------------------------------- doors (ROADMAP_AUSBAU D1)
# One opening sound per biome door plus the boss gate (unlock and slam shut). Names come from
# DoorStyle.open_sound / close_sound. "door_open" above stays the generic fallback.
# All pitches and lengths are TESTWERTE.

def ratchet(dur, step, freqs, vol):
    """Fast metallic clicks (portcullis chain running over a gear)."""
    clicks = []
    count = int(dur / step)
    for i in range(count):
        f = freqs[i % len(freqs)]
        clicks.append(mix(tone(f, 0.018, "square", vol, duty=0.125, attack=0.001, release=0.012),
                          noise(0.015, vol * 0.6, 0.9, attack=0.001, release=0.01)))
    return seq(*clicks, gap=step - 0.018)


def build_doors():
    # Own seed: the sound effects, babble and UI sounds above stay byte-identical.
    random.seed(13)
    doors = {}
    # Crypt: heavy stone and wood grinding open, a dull thud at the end.
    doors["door_open_stone"] = mix(
        noise(0.6, 0.55, 0.05, attack=0.04, release=0.25, cutoff_to=0.03),
        tone(118, 0.5, "saw", 0.16, slide_to=88, attack=0.03, release=0.2, vibrato_rate=11, vibrato_depth=0.03),
        mix(tone(72, 0.22, "sine", 0.7, slide_to=44, release=0.15), noise(0.12, 0.35, 0.2, release=0.1)),
        offsets=[0.0, 0.0, 0.48])
    # Slime grotto: rustling vines and a wet squelch.
    rustle = seq(*[noise(0.07, 0.45, 0.35 + 0.1 * (i % 2), attack=0.005, release=0.05) for i in range(6)], gap=0.025)
    doors["door_open_vines"] = mix(
        rustle,
        tone(320, 0.32, "sine", 0.4, slide_to=120, release=0.15, vibrato_rate=14, vibrato_depth=0.08),
        tone(midi(67), 0.08, "triangle", 0.3, slide_to=midi(74), release=0.05),
        offsets=[0.0, 0.08, 0.45])
    # Shadow realm: runes go out one by one (falling notes), airy shimmer.
    runes = seq(*[tone(midi(n), 0.09, "triangle", 0.35, release=0.07) for n in (81, 78, 74, 69, 66)], gap=0.01)
    doors["door_open_rune"] = mix(
        runes,
        tone(1250, 0.6, "sine", 0.18, slide_to=520, release=0.3, vibrato_rate=9, vibrato_depth=0.03),
        noise(0.65, 0.22, 0.12, attack=0.1, release=0.35),
        offsets=[0.0, 0.0, 0.05])
    # Ember forge: portcullis rattles up, ends with an iron clank.
    doors["door_open_gate"] = mix(
        ratchet(0.48, 0.035, (1500, 1250, 1380), 0.3),
        tone(85, 0.5, "saw", 0.18, slide_to=105, release=0.15),
        noise(0.5, 0.18, 0.5, release=0.2, cutoff_to=0.2),
        mix(tone(620, 0.16, "square", 0.25, duty=0.25, slide_to=540, release=0.12), noise(0.08, 0.5, 0.7, release=0.06)),
        offsets=[0.0, 0.0, 0.0, 0.5])
    # Boss gate: two chains snap, then the wings grind open with a deep, ominous rumble.
    snap = mix(noise(0.06, 0.8, 0.95, attack=0.001, release=0.05),
               tone(1900, 0.08, "square", 0.3, duty=0.125, slide_to=850, attack=0.001, release=0.05))
    doors["door_boss_unlock"] = mix(
        snap, snap,
        tone(68, 1.1, "saw", 0.45, slide_to=50, attack=0.08, release=0.45, vibrato_rate=6, vibrato_depth=0.05),
        noise(1.1, 0.4, 0.06, attack=0.12, release=0.5),
        tone(midi(38), 1.0, "triangle", 0.35, attack=0.15, release=0.5),
        offsets=[0.0, 0.14, 0.22, 0.22, 0.3])
    # Boss gate slams shut behind the player.
    doors["door_boss_close"] = mix(
        noise(0.5, 0.9, 0.12, release=0.4, decay_to=0.3),
        tone(62, 0.45, "sine", 0.9, slide_to=32, release=0.3),
        tone(480, 0.12, "square", 0.18, duty=0.25, slide_to=380, release=0.08))
    for name, samples in doors.items():
        write_wav(SFX_DIR / f"{name}.wav", samples, peak=0.8)
    return len(doors)


if __name__ == "__main__":
    count = build_sfx()
    print(f"{count} sound effects written to {SFX_DIR}")
    babble = build_babble()
    print(f"{babble} boss babble syllables written to {SFX_DIR}")
    ui_count = build_ui()
    print(f"{ui_count} menu sounds written to {SFX_DIR}")
    door_count = build_doors()
    print(f"{door_count} door sounds written to {SFX_DIR}")
