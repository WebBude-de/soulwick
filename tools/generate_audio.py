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


# ---------------------------------------------------------------- room content (ROADMAP_AUSBAU phase 2)
# Abyss fall (A4), combat variants (soul flame, rifts, gravedigger, bounty), wager altar and the
# crumbling floor trial. Until the code switches to these names, the rooms play stand-in sounds
# (dash, hit_enemy, blind, portal, teleport, slam, trap, upgrade). All pitches and lengths are TESTWERTE.

def echo(samples, delay, feedback, count):
    """Simple dark echo: count fading copies, each one more muffled (one-pole low-pass)."""
    parts = [samples]
    offsets = [0.0]
    copy = samples
    for i in range(count):
        smoothed = []
        last = 0.0
        for v in copy:
            last += 0.45 * (v - last)
            smoothed.append(last * feedback)
        copy = smoothed
        parts.append(copy)
        offsets.append(delay * (i + 1))
    return mix(*parts, offsets=offsets)


def clatter(dur, count, freqs, vol, accelerate=1.0):
    """Dry bone clicks spread over dur; accelerate > 1 packs them closer towards the end."""
    parts = []
    offsets = []
    for i in range(count):
        t = (i / max(1, count - 1)) ** (1.0 / accelerate) * dur
        f = random.choice(freqs) * random.uniform(0.92, 1.08)
        parts.append(mix(noise(0.02, vol, 0.9, attack=0.001, release=0.015),
                         tone(f, 0.026, "square", vol * 0.45, duty=0.25, slide_to=f * 0.7, attack=0.001, release=0.016)))
        offsets.append(t)
    return mix(*parts, offsets=offsets)


def build_rooms():
    # Own seed: every sound above stays byte-identical.
    random.seed(17)
    rooms = {}
    # Abyss fall (ChasmRules.FALL_SOUND): a falling whistle over a rush of air that closes like a
    # low-pass, echoing away into the dark. No impact - the player just vanishes.
    whistle = mix(tone(980, 0.42, "sine", 0.4, slide_to=150, attack=0.01, release=0.22, vibrato_rate=7, vibrato_depth=0.02),
                  tone(490, 0.42, "square", 0.07, duty=0.125, slide_to=75, attack=0.01, release=0.22))
    rush = noise(0.46, 0.5, 0.55, attack=0.02, release=0.3, cutoff_to=0.03)
    rooms["pit_fall"] = echo(mix(whistle, rush), 0.075, 0.38, 2)
    # Soul flame hit: a short crackle with a flickering, sinking tone.
    rooms["soul_flame_hit"] = mix(noise(0.09, 0.55, 0.65, attack=0.001, release=0.07),
                                  tone(700, 0.13, "triangle", 0.4, slide_to=520, vibrato_rate=40, vibrato_depth=0.08, release=0.08),
                                  offsets=[0.0, 0.01])
    # Soul flame goes out: a soft thud, an airy hiss that closes down and a dying, wavering tone.
    rooms["soul_flame_out"] = mix(tone(85, 0.25, "sine", 0.7, slide_to=40, release=0.18),
                                  noise(0.85, 0.45, 0.55, attack=0.01, release=0.5, cutoff_to=0.02),
                                  tone(560, 0.8, "triangle", 0.4, slide_to=110, vibrato_rate=11, vibrato_depth=0.06, release=0.45),
                                  offsets=[0.0, 0.0, 0.03])
    # Rift tears open: a ripping noise sweep, then a humming, shimmering wound.
    rooms["rift_open"] = mix(noise(0.22, 0.7, 0.06, attack=0.005, release=0.08, cutoff_to=0.75),
                             tone(72, 0.55, "saw", 0.3, slide_to=64, attack=0.03, release=0.3, vibrato_rate=9, vibrato_depth=0.06),
                             tone(1250, 0.5, "square", 0.08, duty=0.125, vibrato_rate=17, vibrato_depth=0.05, attack=0.05, release=0.3),
                             offsets=[0.0, 0.15, 0.18])
    # Rift summons an enemy (wind-up, VariantRules.RIFT_WIND_UP 0.7 s): a rising warble and a pop.
    rooms["rift_summon"] = mix(tone(170, 0.62, "triangle", 0.45, slide_to=760, vibrato_rate=13, vibrato_depth=0.07, attack=0.08, release=0.05),
                               noise(0.6, 0.25, 0.08, attack=0.4, release=0.05, cutoff_to=0.4),
                               mix(noise(0.05, 0.6, 0.7, attack=0.001, release=0.04),
                                   tone(380, 0.08, "square", 0.25, duty=0.25, slide_to=190, release=0.05)),
                               offsets=[0.0, 0.0, 0.62])
    # Bone heap rattles back together (warning while it rises, RISE_ANIMATION_TIME 1 s).
    rooms["bone_rattle"] = mix(clatter(0.9, 14, (520, 640, 760, 880), 0.55, accelerate=1.8),
                               tone(140, 0.95, "triangle", 0.25, slide_to=260, attack=0.3, release=0.1))
    # Bone heap stands up: a last clatter, a hollow rising tone and a low thump.
    rooms["bone_rise"] = mix(clatter(0.12, 5, (600, 760, 900), 0.6),
                             tone(200, 0.28, "triangle", 0.45, slide_to=380, release=0.15),
                             tone(70, 0.2, "sine", 0.7, slide_to=42, release=0.14),
                             noise(0.18, 0.3, 0.15, release=0.14),
                             offsets=[0.0, 0.05, 0.12, 0.12])
    # Bounty escape hole opens: earth rumble and a hollow gulp downwards.
    rooms["bounty_hole"] = mix(noise(0.6, 0.6, 0.07, attack=0.03, release=0.35),
                               tone(110, 0.55, "sine", 0.6, slide_to=50, attack=0.02, release=0.3),
                               tone(420, 0.3, "triangle", 0.35, slide_to=150, release=0.15),
                               offsets=[0.0, 0.0, 0.1])
    # Bounty escapes into the hole: a quick downward whistle and a muffled plop.
    rooms["bounty_escape"] = mix(tone(820, 0.26, "triangle", 0.4, slide_to=150, release=0.08),
                                 mix(tone(95, 0.16, "sine", 0.6, slide_to=55, release=0.1), noise(0.1, 0.35, 0.12, release=0.08)),
                                 offsets=[0.0, 0.24])
    # Wager accepted: a pact - a low minor chord swelling under a cold bell.
    pact = mix(*[tone(midi(n), 0.85, "triangle", 0.3, attack=0.12, release=0.45, vibrato_rate=5, vibrato_depth=0.01)
                 for n in (45, 48, 52)],
               tone(midi(57), 0.85, "square", 0.06, duty=0.125, attack=0.15, release=0.45))
    bell = mix(tone(midi(81), 0.6, "sine", 0.45, release=0.55, decay_to=0.2),
               tone(midi(81) * 2.76, 0.3, "sine", 0.12, release=0.28, decay_to=0.2))
    rooms["wager_accept"] = mix(pact, bell, offsets=[0.0, 0.02])
    # Wager won: a rising minor-to-major arpeggio ending on a bright shimmer.
    rooms["wager_won"] = seq(*[tone(midi(n), 0.07, "square", 0.3, duty=0.25) for n in (69, 72, 76)],
                             mix(tone(midi(81), 0.38, "square", 0.3, duty=0.25, release=0.28),
                                 tone(midi(73), 0.38, "triangle", 0.4, release=0.28),
                                 tone(midi(93), 0.3, "sine", 0.12, vibrato_rate=24, vibrato_depth=0.02, release=0.25)))
    # Wager lost: two falling notes a tritone apart, then a dull, sinking tail.
    rooms["wager_lost"] = seq(tone(midi(62), 0.12, "square", 0.35, duty=0.5, release=0.04),
                              mix(tone(midi(56), 0.45, "square", 0.3, duty=0.5, slide_to=midi(53), release=0.3),
                                  tone(midi(44), 0.45, "triangle", 0.45, release=0.3),
                                  noise(0.3, 0.2, 0.08, release=0.25)),
                              gap=0.02)
    # Crumbling plate cracks under the feet (CrumbleCourse.step_on): a sharp, dry crack.
    rooms["plate_crack"] = mix(noise(0.04, 0.8, 0.95, attack=0.001, release=0.03),
                               noise(0.03, 0.45, 0.9, attack=0.001, release=0.02),
                               tone(240, 0.06, "square", 0.22, duty=0.125, slide_to=170, attack=0.001, release=0.04),
                               offsets=[0.0, 0.045, 0.0])
    # Crumbling plate breaks away (CRUMBLE_DELAY over): crunching stone, debris falling into the dark.
    rooms["plate_break"] = echo(mix(noise(0.3, 0.75, 0.35, attack=0.002, release=0.22, decay_to=0.3, cutoff_to=0.05),
                                    tone(90, 0.24, "sine", 0.6, slide_to=45, release=0.16),
                                    clatter(0.28, 6, (300, 380, 460), 0.35),
                                    offsets=[0.0, 0.0, 0.05]), 0.08, 0.3, 1)
    for name, samples in rooms.items():
        write_wav(SFX_DIR / f"{name}.wav", samples, peak=0.8)
    return len(rooms)


# ---------------------------------------------------------------- room kinds v2 (ROADMAP_AUSBAU R9)
# Sounds from docs/design/responses/09_audio.md: enemy sources (warning while the source
# glows ~1 s), the intro pattern (door, banner, countdown), wave gong, souls, collapse, escort,
# relic, braziers, slime hops, stone guardians, lantern and torch. Only new names: every file above
# stays byte-identical (own seed). All pitches and lengths are TESTWERTE.

def lp_coef(hz):
    """One-pole low-pass coefficient for a cutoff in Hz (for noise(cutoff=...))."""
    return 1.0 - math.exp(-TAU * hz / SR)


def band_noise(dur, low_hz, high_hz, vol=0.5, attack=0.002, release=0.05, decay_to=1.0):
    """Rough band-pass noise: low-passed at high_hz minus low-passed at low_hz."""
    n = max(1, int(dur * SR))
    out = [0.0] * n
    a_hi = lp_coef(high_hz)
    a_lo = lp_coef(low_hz)
    hi = lo = 0.0
    for i in range(n):
        x = random.uniform(-1.0, 1.0)
        hi += a_hi * (x - hi)
        lo += a_lo * (x - lo)
        out[i] = (hi - lo) * 2.0 * vol * envelope(i, n, attack, release, decay_to)
    return out


def tremolo(samples, rate, depth, phase=0.0):
    return [v * (1.0 - depth * (0.5 + 0.5 * math.sin(TAU * (rate * i / SR + phase)))) for i, v in enumerate(samples)]


def bell(freq, dur, vol, ratios=(1.0, 2.76, 5.4), weights=(1.0, 0.35, 0.12)):
    """Struck metal or glass: a sine with inharmonic partials, each decaying faster than the last."""
    parts = [tone(freq * r, dur / (1.0 + k * 0.8), "sine", vol * w, attack=0.002, release=dur * 0.6 / (1.0 + k), decay_to=0.15)
             for k, (r, w) in enumerate(zip(ratios, weights))]
    return mix(*parts)


def chord(notes, dur, kind="triangle", vol=0.3, attack=0.02, release=None):
    release = dur * 0.6 if release is None else release
    return mix(*[tone(midi(n), dur, kind, vol, attack=attack, release=release) for n in notes])


def crackle(dur, count, vol, cutoff=0.8):
    """Fire crackle: short random noise pops."""
    parts = []
    offsets = []
    for _ in range(count):
        parts.append(noise(random.uniform(0.006, 0.016), vol * random.uniform(0.4, 1.0), cutoff, attack=0.0005, release=0.005))
        offsets.append(random.uniform(0.0, dur))
    return mix(*parts, offsets=offsets)


def build_room_kinds():
    # Own seed: every sound above stays byte-identical.
    random.seed(19)
    fx = {}
    # --- enemy sources (R2): played with the 1 s warning glow, the enemy appears at the end.
    # Grave: earth crunches open (low noise ~300 Hz), bones clatter in it.
    fx["spawn_grave"] = mix(noise(0.55, 0.7, lp_coef(300), attack=0.05, release=0.25, decay_to=0.5),
                            tremolo(noise(0.5, 0.35, lp_coef(900), attack=0.08, release=0.2), 13, 0.7),
                            clatter(0.4, 7, (520, 660, 820), 0.45, accelerate=1.5),
                            tone(70, 0.3, "sine", 0.5, slide_to=45, release=0.2),
                            offsets=[0.0, 0.05, 0.3, 0.55])
    # Puddle: three bubbles rising 150 -> 250 Hz, then a wet plop.
    bubbles = [tone(f, 0.11, "sine", 0.55, slide_to=f * 1.6, attack=0.01, release=0.04) for f in (150, 190, 250)]
    fx["spawn_puddle"] = mix(*bubbles,
                             noise(0.08, 0.45, lp_coef(800), release=0.06),
                             tone(110, 0.14, "sine", 0.5, slide_to=60, release=0.08),
                             offsets=[0.0, 0.17, 0.32, 0.5, 0.5])
    # Floor rift: a rising sine 100 -> 400 Hz under a whisper (band noise with slow tremolo).
    fx["spawn_rift"] = mix(tone(100, 0.85, "sine", 0.55, slide_to=400, attack=0.12, release=0.12, vibrato_rate=6, vibrato_depth=0.03),
                           tremolo(band_noise(0.85, 700, 1600, 0.45, attack=0.15, release=0.2), 5.5, 0.8),
                           tone(400, 0.12, "triangle", 0.3, slide_to=520, release=0.08),
                           offsets=[0.0, 0.0, 0.82])
    # Lava vent: hissing steam over a sub drone, ends in a short burst.
    fx["spawn_vent"] = mix(noise(0.8, 0.45, 0.9, attack=0.15, release=0.2),
                           tone(48, 0.85, "sine", 0.7, slide_to=58, attack=0.2, release=0.25),
                           tone(96, 0.85, "saw", 0.12, slide_to=110, attack=0.2, release=0.25),
                           mix(noise(0.18, 0.7, 0.5, release=0.14), crackle(0.2, 8, 0.6)),
                           offsets=[0.0, 0.0, 0.0, 0.72])
    # Wall gate: chain pulled over a gear, metal rattling, the gate grinds up and stops with a clank.
    fx["spawn_gate"] = mix(ratchet(0.7, 0.045, (1400, 1180, 1300, 1050), 0.32),
                           tone(80, 0.75, "saw", 0.2, slide_to=100, attack=0.05, release=0.2, vibrato_rate=9, vibrato_depth=0.04),
                           noise(0.75, 0.2, lp_coef(1500), attack=0.05, release=0.2),
                           mix(tone(560, 0.14, "square", 0.22, duty=0.25, slide_to=480, release=0.1), noise(0.06, 0.5, 0.7, release=0.05)),
                           offsets=[0.0, 0.0, 0.0, 0.74])
    # Sarcophagus: the stone lid grinds aside and drops with a dull thud and dust.
    grind = tremolo(noise(0.6, 0.6, lp_coef(450), attack=0.06, release=0.1), 17, 0.6)
    fx["spawn_sarcophagus"] = mix(grind,
                                  tone(62, 0.6, "saw", 0.18, slide_to=55, attack=0.06, release=0.1, vibrato_rate=17, vibrato_depth=0.05),
                                  tone(58, 0.3, "sine", 0.85, slide_to=34, release=0.22),
                                  noise(0.4, 0.3, lp_coef(2500), attack=0.01, release=0.35, decay_to=0.2),
                                  offsets=[0.0, 0.0, 0.62, 0.64])
    # --- intro pattern (R3): door shuts with a hall, banner chord (minor = fight, major = calm), 3-2-1, go.
    fx["intro_door"] = echo(mix(noise(0.22, 0.85, lp_coef(1400), release=0.18, decay_to=0.3),
                                tone(68, 0.3, "sine", 0.9, slide_to=38, release=0.22),
                                tone(420, 0.08, "square", 0.15, duty=0.25, slide_to=330, release=0.06)), 0.11, 0.42, 3)
    fx["intro_banner_combat"] = mix(chord((57, 60, 64), 0.55, "triangle", 0.32, attack=0.01),
                                    chord((45,), 0.55, "square", 0.12, attack=0.01),
                                    tone(midi(69), 0.3, "square", 0.08, duty=0.125, release=0.2))
    fx["intro_banner_calm"] = mix(chord((60, 64, 67), 0.6, "triangle", 0.3, attack=0.03),
                                  tone(midi(72), 0.5, "sine", 0.2, attack=0.05, release=0.35, vibrato_rate=5, vibrato_depth=0.01))
    fx["countdown_tick"] = tone(800, 0.04, "square", 0.4, duty=0.5, attack=0.001, release=0.015)
    fx["countdown_go"] = mix(tone(1200, 0.16, "square", 0.38, duty=0.5, attack=0.001, release=0.08),
                             tone(600, 0.16, "triangle", 0.3, attack=0.001, release=0.08))
    # --- progress
    # Wave done: gong (220 Hz with inharmonic partials, ~1.2 s decay).
    fx["wave_gong"] = mix(bell(220, 1.4, 0.7, ratios=(1.0, 2.0, 2.76, 4.1), weights=(1.0, 0.4, 0.3, 0.12)),
                          tone(110, 0.9, "sine", 0.3, release=0.7, decay_to=0.2),
                          noise(0.05, 0.25, 0.4, release=0.04))
    # Soul collected: glass ping going up.
    fx["soul_collect"] = mix(bell(midi(84), 0.35, 0.45), bell(midi(88), 0.35, 0.4), bell(midi(91), 0.45, 0.4),
                             offsets=[0.0, 0.05, 0.1])
    # Soul fades unseen: a soft, airy shimmer sinking away.
    fx["soul_fade"] = mix(tone(midi(88), 0.55, "sine", 0.35, slide_to=midi(76), attack=0.02, release=0.4, vibrato_rate=11, vibrato_depth=0.02),
                          band_noise(0.55, 1500, 4000, 0.25, attack=0.05, release=0.4))
    # --- collapse: three dry cracks, then stone sliding down (falling low-pass) with a sub.
    fx["collapse_crack"] = mix(*[mix(noise(0.03, 0.85, 0.95, attack=0.0005, release=0.02),
                                     tone(f, 0.04, "square", 0.2, duty=0.125, slide_to=f * 0.7, attack=0.0005, release=0.03))
                                 for f in (260, 210, 300)],
                               offsets=[0.0, 0.07, 0.16])
    fx["collapse_fall"] = mix(noise(0.45, 0.8, lp_coef(1800), attack=0.005, release=0.25, decay_to=0.25, cutoff_to=lp_coef(250)),
                              tone(64, 0.4, "sine", 0.8, slide_to=36, release=0.28),
                              clatter(0.35, 6, (280, 340, 420), 0.35),
                              offsets=[0.0, 0.03, 0.12])
    # --- escort: a short call for help, no word ("hm-hmm!" rising, a little worried vibrato).
    call_a = mix(tone(520, 0.12, "triangle", 0.5, slide_to=640, attack=0.01, release=0.04, vibrato_rate=9, vibrato_depth=0.02),
                 tone(1040, 0.12, "square", 0.08, duty=0.25, slide_to=1280, attack=0.01, release=0.04))
    call_b = mix(tone(600, 0.22, "triangle", 0.55, slide_to=760, attack=0.01, release=0.1, vibrato_rate=12, vibrato_depth=0.035),
                 tone(1200, 0.22, "square", 0.08, duty=0.25, slide_to=1520, attack=0.01, release=0.1))
    fx["escort_help"] = seq(call_a, call_b, gap=0.05)
    # --- relic: golden arpeggio over a warm hum; placing it: a deep thunk and a swelling major chord.
    fx["relic_pickup"] = mix(seq(*[tone(midi(n), 0.06, "square", 0.25, duty=0.25) for n in (76, 79, 83)],
                                 tone(midi(88), 0.3, "square", 0.25, duty=0.25, release=0.22)),
                             tone(midi(52), 0.5, "triangle", 0.35, attack=0.04, release=0.3, vibrato_rate=5, vibrato_depth=0.01))
    fx["relic_place"] = mix(tone(70, 0.28, "sine", 0.85, slide_to=42, release=0.2),
                            noise(0.1, 0.4, lp_coef(1200), release=0.08),
                            chord((64, 68, 71, 76), 0.9, "triangle", 0.22, attack=0.15, release=0.5),
                            bell(midi(88), 0.6, 0.25),
                            offsets=[0.0, 0.0, 0.12, 0.2])
    # --- fire: brazier catches with a whoosh (opening low-pass) and crackles; torch is shorter.
    whoosh = noise(0.32, 0.6, lp_coef(400), attack=0.04, release=0.12, cutoff_to=lp_coef(3500))
    fx["brazier_light"] = mix(whoosh,
                              tone(90, 0.35, "sine", 0.45, slide_to=140, attack=0.03, release=0.2),
                              crackle(0.45, 14, 0.55),
                              offsets=[0.0, 0.0, 0.2])
    fx["torch_ignite"] = mix(noise(0.18, 0.55, lp_coef(700), attack=0.02, release=0.08, cutoff_to=lp_coef(4500)),
                             crackle(0.25, 8, 0.5),
                             offsets=[0.0, 0.12])
    # --- slimes: hop blip 180 -> 90 Hz and a wet landing (low-passed noise 800 Hz).
    fx["slime_hop"] = tone(180, 0.12, "sine", 0.6, slide_to=90, attack=0.004, release=0.05)
    fx["slime_land"] = mix(noise(0.06, 0.7, lp_coef(800), attack=0.001, release=0.045),
                           tone(95, 0.07, "sine", 0.45, slide_to=60, release=0.04))
    # --- stone guardians: grinding while they move in the dark, a clank when they freeze in light.
    fx["stone_grind"] = mix(tremolo(noise(0.45, 0.7, lp_coef(350), attack=0.05, release=0.12), 21, 0.65),
                            tone(55, 0.45, "saw", 0.16, vibrato_rate=21, vibrato_depth=0.06, attack=0.05, release=0.12))
    fx["stone_clank"] = mix(tone(85, 0.18, "sine", 0.8, slide_to=55, release=0.12),
                            noise(0.05, 0.7, lp_coef(3000), attack=0.0005, release=0.04),
                            bell(310, 0.35, 0.22, ratios=(1.0, 2.4, 3.9), weights=(1.0, 0.4, 0.2)))
    # --- lantern: glass clink and a warm rising note; into the socket: click and a calm chord.
    fx["lantern_pickup"] = mix(bell(midi(84), 0.3, 0.3),
                               tone(midi(64), 0.4, "triangle", 0.35, slide_to=midi(67), attack=0.02, release=0.25),
                               crackle(0.25, 5, 0.3),
                               offsets=[0.0, 0.03, 0.05])
    fx["lantern_socket"] = mix(mix(noise(0.03, 0.7, 0.9, attack=0.0005, release=0.02),
                                   tone(900, 0.05, "square", 0.25, duty=0.125, slide_to=700, release=0.03)),
                               chord((60, 67, 72), 0.7, "triangle", 0.25, attack=0.12, release=0.4),
                               tone(midi(84), 0.6, "sine", 0.15, attack=0.15, release=0.4, vibrato_rate=5, vibrato_depth=0.01),
                               offsets=[0.0, 0.06, 0.1])
    # Short, frequent sounds a little quieter than the effects (they repeat a lot).
    peaks = {"countdown_tick": 0.4, "countdown_go": 0.55, "slime_hop": 0.4, "slime_land": 0.55, "soul_collect": 0.7,
             "soul_fade": 0.6, "stone_grind": 0.65, "spawn_puddle": 0.7, "spawn_rift": 0.7}
    for name, samples in fx.items():
        write_wav(SFX_DIR / f"{name}.wav", samples, peak=peaks.get(name, 0.8))
    return len(fx)


# ---------------------------------------------------------------- side view (M5 round 2)
# Gang segments in side view: jump, double jump, landing (soft and hard), wall slide, crumbling
# ledge and the low drone of the black fade. Own seed: every sound above stays byte-identical.
# Only this block: python tools/generate_audio.py side   (TESTWERTE: pitches and lengths)

def build_side():
    random.seed(23)
    fx = {}
    # Jump: a short springy blip 260 -> 520 Hz over a soft puff of air.
    fx["side_jump"] = mix(tone(260, 0.09, "square", 0.35, duty=0.25, slide_to=520, attack=0.002, release=0.04),
                          noise(0.07, 0.35, 0.5, attack=0.002, release=0.05))
    # Double jump: a higher whoosh (band noise rising) with a bright two-note sparkle.
    fx["side_double_jump"] = mix(tone(520, 0.12, "triangle", 0.4, slide_to=1040, attack=0.003, release=0.06),
                                 band_noise(0.16, 1200, 3200, 0.35, attack=0.01, release=0.1),
                                 bell(midi(88), 0.18, 0.18),
                                 offsets=[0.0, 0.0, 0.05])
    # Landing: a soft thud (sine 120 -> 60 Hz) and a little grit.
    fx["side_land"] = mix(tone(120, 0.08, "sine", 0.6, slide_to=60, attack=0.001, release=0.05),
                          noise(0.05, 0.4, lp_coef(1200), attack=0.001, release=0.04))
    # Hard landing: a heavier thump, a low sub and rubble crumbs afterwards.
    fx["side_land_hard"] = mix(tone(90, 0.16, "sine", 0.8, slide_to=42, attack=0.001, release=0.1),
                               noise(0.1, 0.6, lp_coef(600), attack=0.001, release=0.08),
                               clatter(0.22, 5, (380, 520, 640), 0.3, accelerate=1.4),
                               offsets=[0.0, 0.0, 0.06])
    # Wall slide: a short scrape (band noise with fast tremolo), played every few tenths of a second.
    fx["side_wall_slide"] = tremolo(band_noise(0.26, 500, 1800, 0.45, attack=0.02, release=0.08), 28, 0.5)
    # Crumbling ledge: a crack, then stones falling and bouncing.
    fx["side_crumble"] = mix(noise(0.05, 0.7, lp_coef(3000), attack=0.0005, release=0.04),
                             tone(140, 0.2, "sine", 0.5, slide_to=70, release=0.12),
                             clatter(0.5, 9, (300, 420, 560, 700), 0.4, accelerate=1.6),
                             offsets=[0.0, 0.0, 0.08])
    # Drone of the black fade ("Abstieg"): a low hum with a slow beat and dark air, 1.6 s.
    fx["side_drone"] = mix(tone(55, 1.6, "sine", 0.6, attack=0.25, release=0.6),
                           tone(55.8, 1.6, "sine", 0.45, attack=0.25, release=0.6),
                           tone(82.5, 1.6, "saw", 0.08, attack=0.4, release=0.6),
                           tremolo(band_noise(1.6, 80, 400, 0.25, attack=0.4, release=0.6), 0.7, 0.5))
    peaks = {"side_jump": 0.5, "side_double_jump": 0.55, "side_land": 0.5, "side_land_hard": 0.75,
             "side_wall_slide": 0.35, "side_crumble": 0.75, "side_drone": 0.7}
    for name, samples in fx.items():
        write_wav(SFX_DIR / f"{name}.wav", samples, peak=peaks.get(name, 0.7))
    return len(fx)


# ---------------------------------------------------------------- village (report #ec4f0b9f)
# A villager the player runs into hops aside with a small confused "hm?" (Villager.dodge_sound).
# Own seed: every sound above stays byte-identical.
# Only this block: python tools/generate_audio.py village   (TESTWERTE: pitches and lengths)

def build_village():
    random.seed(31)
    fx = {}
    # "hm?": a short closed hum (soft square through a low-pass feel) and a rising, slightly wobbly
    # vowel 300 -> 470 Hz with a breath of air; about a quarter second, cute rather than annoyed.
    hum = mix(tone(250, 0.07, "triangle", 0.5, attack=0.012, release=0.03),
              tone(500, 0.07, "sine", 0.12, attack=0.012, release=0.03))
    rise = mix(tone(300, 0.16, "triangle", 0.55, slide_to=470, attack=0.015, release=0.07,
                    vibrato_rate=9.0, vibrato_depth=0.02),
               tone(600, 0.16, "sine", 0.14, slide_to=940, attack=0.015, release=0.07),
               band_noise(0.12, 900, 2600, 0.06, attack=0.02, release=0.08))
    fx["villager_huh"] = seq(hum, rise, gap=0.025)
    peaks = {"villager_huh": 0.5}
    for name, samples in fx.items():
        write_wav(SFX_DIR / f"{name}.wav", samples, peak=peaks.get(name, 0.6))
    return len(fx)


if __name__ == "__main__":
    import sys
    if sys.argv[1:] == ["side"]:
        side_count = build_side()
        print(f"{side_count} side view sounds (M5) written to {SFX_DIR}")
        raise SystemExit(0)
    if sys.argv[1:] == ["village"]:
        village_count = build_village()
        print(f"{village_count} village sounds written to {SFX_DIR}")
        raise SystemExit(0)
    count = build_sfx()
    print(f"{count} sound effects written to {SFX_DIR}")
    babble = build_babble()
    print(f"{babble} boss babble syllables written to {SFX_DIR}")
    ui_count = build_ui()
    print(f"{ui_count} menu sounds written to {SFX_DIR}")
    door_count = build_doors()
    print(f"{door_count} door sounds written to {SFX_DIR}")
    room_count = build_rooms()
    print(f"{room_count} room content sounds written to {SFX_DIR}")
    kind_count = build_room_kinds()
    print(f"{kind_count} room kind sounds (R9) written to {SFX_DIR}")
    side_count = build_side()
    print(f"{side_count} side view sounds (M5) written to {SFX_DIR}")
    village_count = build_village()
    print(f"{village_count} village sounds written to {SFX_DIR}")
