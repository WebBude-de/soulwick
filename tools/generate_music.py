"""Renders every music loop and ambient bed of the game as soft chiptune WAVs (pure Python).

Usage (from the project root):
    python tools/generate_music.py               # everything (uses all CPU cores)
    python tools/generate_music.py crypt boss_   # only names containing one of the words
    python tools/generate_music.py --list        # names, tempo, key and bars
    python tools/generate_music.py --measure     # length, peak, RMS and loop seam of the files on disk

Output (mono, 16 bit, seamless loops):
    audio/music/village|dungeon|boss.wav          44.1 kHz, D-068/D-072, fallbacks (unchanged)
    audio/music/dungeon_<biome>.wav               32 kHz, one track per biome (D-092)
    audio/music/dungeon_<biome>_intense.wav       same tempo and bars plus drums, champion rooms
    audio/music/boss_<boss>.wav, boss_<boss>_p2   32 kHz, one theme per boss; phase two is faster
    audio/ambient/ambient_<biome|village>.wav     22.05 kHz, quiet bed under the music
    audio/music/transition_<biome>.wav            32 kHz one-shot when a biome is entered; leads into
                                                  bar one of the loop after its last 1.5 s (tail)
    audio/music/victory_<boss>.wav                32 kHz one-shot when the boss falls (bVI-bVII-I)
Replace any file with your own of the same name (.wav, .ogg or .mp3) to change it; MusicPlayer
prefers .ogg/.mp3 over the generated .wav.

Sound design: band-limited pulse/saw waves (PolyBLEP), triangles, drawbar organ, FM glass,
additive bells and mallets, low-pass filters per voice, synthesized drums, a circular echo and
reverb (both wrap around the loop, so there is no seam) and a soft limiter. Every track is
matched to the loudness of the legacy loops (RMS after a 150 Hz high-pass). Melodies are
hand-written; the only randomness (noise, ambient event times) uses fixed seeds.
"""
import math
import os
import random
import sys
import wave
import zlib
from array import array
from multiprocessing import Pool
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "audio" / "music"
AMBIENT_OUT = ROOT / "audio" / "ambient"
SR = 44100  # legacy loops
MUSIC_SR = 32000  # new loops: the voices are low-passed far below 16 kHz, files stay small
AMBIENT_SR = 22050
TAU = 2.0 * math.pi
REST = None
CEILING = 0.89  # -1 dBFS
# Loudness targets in dB (RMS after a 150 Hz high-pass). Legacy: dungeon -14.3, boss -14.7.
LOUDNESS_DUNGEON = -14.5
LOUDNESS_INTENSE = -14.0
LOUDNESS_BOSS = -14.5
LOUDNESS_BOSS_P2 = -13.8
# Ambient beds sit well below the music (TESTWERT; the player adds MusicPlayer.AMBIENT_VOLUME_DB).
LOUDNESS_AMBIENT = -30.0


def midi_freq(note):
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def polyblep(t, dt):
    if t < dt:
        t /= dt
        return t + t - t * t - 1.0
    if t > 1.0 - dt:
        t = (t - 1.0) / dt
        return t * t + t + t + 1.0
    return 0.0


# =================================================================== legacy loops (D-072)
# Kept exactly as composed in D-072 so village/dungeon/boss stay byte-identical fallbacks.

class Voice:
    """One instrument rendered into its own buffer."""

    def __init__(self, length, wave="pulse", duty=0.5, cutoff=3000.0, attack=0.01, decay=0.18,
                 sustain=0.55, release=0.08, vibrato_depth=0.0, vibrato_rate=5.0, sub=0.0):
        self.buf = [0.0] * length
        self.wave = wave
        self.duty = duty
        self.alpha = 1.0 - math.exp(-TAU * cutoff / SR)
        self.attack = attack
        self.decay = decay
        self.sustain = sustain
        self.release = release
        self.vibrato_depth = vibrato_depth
        self.vibrato_rate = vibrato_rate
        self.sub = sub

    def note(self, start, duration, note, volume):
        if note is None:
            return
        freq = midi_freq(note)
        n_on = int(duration * SR)
        n = n_on + int(self.release * SR)
        phase = 0.0
        sub_phase = 0.0
        lp = 0.0
        buf = self.buf
        length = len(buf)
        a_n = max(1, int(self.attack * SR))
        d_n = max(1, int(self.decay * SR))
        r_n = max(1, int(self.release * SR))
        for i in range(n):
            # Envelope: attack -> decay to sustain -> release after note off.
            if i < a_n:
                env = i / a_n
            elif i < a_n + d_n:
                env = 1.0 - (1.0 - self.sustain) * (i - a_n) / d_n
            else:
                env = self.sustain
            if i >= n_on:
                env *= max(0.0, 1.0 - (i - n_on) / r_n)
            f = freq
            if self.vibrato_depth and i > a_n + d_n:
                f *= 1.0 + self.vibrato_depth * math.sin(TAU * self.vibrato_rate * i / SR)
            dt = f / SR
            phase += dt
            if phase >= 1.0:
                phase -= 1.0
            if self.wave == "pulse":
                v = 1.0 if phase < self.duty else -1.0
                v += polyblep(phase, dt)
                v -= polyblep((phase - self.duty) % 1.0, dt)
            elif self.wave == "triangle":
                v = 4.0 * phase - 1.0 if phase < 0.5 else 3.0 - 4.0 * phase
            else:
                v = math.sin(TAU * phase)
            if self.sub:
                sub_phase = (sub_phase + dt * 0.5) % 1.0
                v += self.sub * math.sin(TAU * sub_phase)
            lp += self.alpha * (v - lp)
            buf[(start + i) % length] += lp * env * volume


class Drums:
    def __init__(self, length):
        self.buf = [0.0] * length
        self.seed = 12345

    def _noise(self):
        self.seed = (self.seed * 1103515245 + 12345) & 0x7FFFFFFF
        return self.seed / 0x3FFFFFFF - 1.0

    def kick(self, start, volume):
        n = int(0.22 * SR)
        phase = 0.0
        for i in range(n):
            t = i / SR
            f = 45.0 + 110.0 * math.exp(-t * 28.0)
            phase += f / SR
            env = math.exp(-t * 14.0)
            self.buf[(start + i) % len(self.buf)] += math.sin(TAU * phase) * env * volume

    def snare(self, start, volume):
        n = int(0.18 * SR)
        lp = 0.0
        phase = 0.0
        for i in range(n):
            t = i / SR
            lp += 0.45 * (self._noise() - lp)
            phase += 190.0 / SR
            body = math.sin(TAU * phase) * math.exp(-t * 30.0) * 0.5
            self.buf[(start + i) % len(self.buf)] += (lp * math.exp(-t * 18.0) + body) * volume

    def hat(self, start, volume, length=0.035):
        n = int(length * SR)
        last = 0.0
        for i in range(n):
            x = self._noise()
            hp = x - last  # crude high-pass
            last = x
            self.buf[(start + i) % len(self.buf)] += hp * math.exp(-i / (n * 0.35)) * volume


def echo(buf, delay_samples, feedback, mix):
    """Feedback delay that wraps around the loop, so the loop stays seamless."""
    length = len(buf)
    wet = [0.0] * length
    line = [0.0] * delay_samples
    pos = 0
    for _ in range(2):  # second pass reaches the steady state across the loop seam
        for i in range(length):
            delayed = line[pos]
            line[pos] = buf[i] + delayed * feedback
            pos = (pos + 1) % delay_samples
            wet[i] = delayed
    return [d + w * mix for d, w in zip(buf, wet)]


def write(name, layers):
    length = len(layers[0])
    mixed = [0.0] * length
    for layer in layers:
        for i, v in enumerate(layer):
            mixed[i] += v
    mixed = [math.tanh(v * 1.2) for v in mixed]
    peak = max(1e-9, max(abs(v) for v in mixed))
    scale = 0.8 / peak
    data = array("h", (int(v * scale * 32767) for v in mixed))
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    return f"{name}: {length / SR:.1f} s (legacy)"


def chord(root, quality):
    third = 3 if quality == "m" else 4
    return [root, root + third, root + 7]


def render(name, bpm, progression, melody, style):
    step = 60.0 / bpm / 4.0  # one 16th note in seconds
    bars = len(progression)
    length = int(bars * 16 * step * SR)
    s = lambda steps: int(steps * step * SR)  # noqa: E731

    lead = Voice(length, style["lead_wave"], style.get("lead_duty", 0.5), style["lead_cutoff"],
                 attack=style.get("lead_attack", 0.012), decay=0.2, sustain=0.6, release=0.1,
                 vibrato_depth=style.get("vibrato", 0.004), vibrato_rate=5.0)
    harmony = Voice(length, style.get("arp_wave", "triangle"), 0.5, style.get("arp_cutoff", 2400.0),
                    attack=0.004, decay=0.09, sustain=0.25, release=0.05)
    pad = Voice(length, "pulse", 0.5, style.get("pad_cutoff", 900.0), attack=0.2, decay=0.4, sustain=0.7, release=0.3)
    bass = Voice(length, style["bass_wave"], 0.5, style["bass_cutoff"], attack=0.005, decay=0.12,
                 sustain=0.7, release=0.04, sub=style.get("bass_sub", 0.0))
    drums = Drums(length)

    # Lead melody: list of bars, each a list of (note, steps).
    position = 0
    for bar in melody:
        for note, steps in bar:
            lead.note(s(position), steps * step * 0.95, note, style["lead_vol"])
            position += steps

    for bar_index, (root_name, quality) in enumerate(progression):
        root = style["key"] + root_name
        start = bar_index * 16
        tones = chord(root, quality)
        # Pad chord
        if style.get("pad_vol", 0.0) > 0.0:
            for t in tones:
                pad.note(s(start), 16 * step, t + 48 - style["key"] + style["pad_octave"], style["pad_vol"])
        # Arpeggio / broken chords
        arp_step = style["arp_step"]
        arp_notes = tones + [root + 12] if style.get("arp_up", True) else [tones[0], tones[2], tones[1], tones[2]]
        for i, k in enumerate(range(0, 16, arp_step)):
            harmony.note(s(start + k), arp_step * step * 0.9, arp_notes[i % len(arp_notes)] + style["arp_octave"], style["arp_vol"])
        # Bass pattern (offsets in semitones relative to the root)
        for k, offset in style["bass_pattern"]:
            bass.note(s(start + k), style["bass_len"] * step, root + offset + style["bass_octave"], style["bass_vol"])
        # Drums
        for k in style["kicks"]:
            drums.kick(s(start + k), style["kick_vol"])
        for k in style["snares"]:
            drums.snare(s(start + k), style["snare_vol"])
        for k in style["hats"]:
            drums.hat(s(start + k), style["hat_vol"])

    lead_buf = echo(lead.buf, s(3), 0.3, style.get("echo", 0.25))
    return write(name, [lead_buf, harmony.buf, pad.buf, bass.buf, drums.buf])


# Note numbers: C4 = 60, A4 = 69.

DUNGEON_MELODY = [
    [(76, 4), (74, 2), (72, 2), (71, 4), (69, 4)],
    [(69, 2), (72, 2), (77, 4), (76, 4), (72, 4)],
    [(67, 4), (72, 2), (76, 2), (79, 6), (76, 2)],
    [(74, 4), (71, 4), (67, 8)],
    [(76, 4), (74, 2), (72, 2), (71, 4), (69, 4)],
    [(69, 2), (72, 2), (77, 4), (81, 4), (79, 2), (77, 2)],
    [(76, 4), (74, 4), (72, 4), (71, 4)],
    [(68, 8), (64, 4), (REST, 4)],
    [(77, 4), (76, 2), (74, 2), (69, 8)],
    [(72, 4), (71, 2), (69, 2), (64, 8)],
    [(65, 2), (69, 2), (72, 4), (77, 4), (76, 4)],
    [(76, 6), (74, 2), (72, 8)],
    [(74, 4), (77, 4), (81, 4), (79, 2), (77, 2)],
    [(76, 4), (74, 4), (71, 4), (68, 4)],
    [(69, 8), (72, 4), (76, 4)],
    [(71, 8), (68, 8)],
]
DUNGEON_CHORDS = [(0, "m"), (8, ""), (3, ""), (10, ""), (0, "m"), (8, ""), (7, ""), (7, ""),
                  (5, "m"), (0, "m"), (8, ""), (3, ""), (5, "m"), (7, ""), (0, "m"), (7, "")]

BOSS_MELODY = [
    [(74, 2), (74, 2), (77, 2), (74, 2), (81, 4), (79, 2), (77, 2)],
    [(76, 2), (77, 2), (76, 2), (74, 2), (73, 4), (69, 4)],
    [(74, 4), (77, 4), (82, 4), (81, 2), (79, 2)],
    [(76, 4), (79, 4), (84, 4), (82, 2), (81, 2)],
    [(74, 2), (74, 2), (77, 2), (74, 2), (81, 4), (79, 2), (77, 2)],
    [(76, 2), (77, 2), (79, 2), (76, 2), (73, 8)],
    [(76, 4), (81, 4), (76, 4), (73, 4)],
    [(69, 12), (REST, 4)],
    [(79, 4), (82, 2), (81, 2), (79, 4), (74, 4)],
    [(70, 2), (74, 2), (79, 4), (77, 4), (74, 4)],
    [(81, 4), (79, 2), (77, 2), (76, 4), (74, 4)],
    [(77, 2), (76, 2), (74, 2), (73, 2), (74, 8)],
    [(77, 4), (74, 4), (70, 4), (74, 4)],
    [(79, 4), (76, 4), (72, 4), (76, 4)],
    [(76, 2), (77, 2), (76, 2), (74, 2), (73, 4), (76, 4)],
    [(81, 8), (REST, 8)],
]
BOSS_CHORDS = [(0, "m"), (0, "m"), (8, ""), (10, ""), (0, "m"), (0, "m"), (7, ""), (7, ""),
               (5, "m"), (5, "m"), (0, "m"), (0, "m"), (8, ""), (10, ""), (7, ""), (7, "")]

VILLAGE_MELODY = [
    [(76, 6), (74, 2), (72, 4), (67, 4)],
    [(69, 6), (71, 2), (72, 4), (76, 4)],
    [(77, 6), (76, 2), (74, 4), (72, 4)],
    [(74, 12), (REST, 4)],
    [(76, 6), (74, 2), (72, 4), (76, 4)],
    [(79, 6), (77, 2), (76, 4), (72, 4)],
    [(74, 4), (76, 4), (77, 4), (81, 4)],
    [(79, 12), (REST, 4)],
    [(81, 6), (79, 2), (77, 4), (72, 4)],
    [(71, 6), (72, 2), (74, 8)],
    [(76, 6), (74, 2), (71, 4), (67, 4)],
    [(69, 6), (72, 2), (76, 8)],
    [(77, 4), (76, 4), (74, 4), (69, 4)],
    [(71, 4), (74, 4), (79, 8)],
    [(76, 8), (72, 8)],
    [(72, 12), (REST, 4)],
]
VILLAGE_CHORDS = [(0, ""), (9, "m"), (5, ""), (7, ""), (0, ""), (9, "m"), (2, "m"), (7, ""),
                  (5, ""), (7, ""), (4, "m"), (9, "m"), (2, "m"), (7, ""), (0, ""), (0, "")]


def legacy_dungeon():
    return render("dungeon", 128, DUNGEON_CHORDS, DUNGEON_MELODY, {
        "key": 57,
        "lead_wave": "pulse", "lead_duty": 0.5, "lead_cutoff": 2600.0, "lead_vol": 0.20, "vibrato": 0.003,
        "arp_wave": "triangle", "arp_step": 2, "arp_octave": 0, "arp_vol": 0.10, "arp_cutoff": 2200.0,
        "pad_vol": 0.035, "pad_octave": 0, "pad_cutoff": 700.0,
        "bass_wave": "pulse", "bass_cutoff": 700.0, "bass_vol": 0.32, "bass_sub": 0.5, "bass_octave": -24, "bass_len": 1.8,
        "bass_pattern": [(0, 0), (2, 0), (4, 12), (6, 0), (8, 7), (10, 0), (12, 12), (14, 7)],
        "kicks": (0, 8, 11), "snares": (4, 12), "hats": (2, 6, 10, 14),
        "kick_vol": 0.9, "snare_vol": 0.35, "hat_vol": 0.10, "echo": 0.22,
    })


def legacy_boss():
    return render("boss", 150, BOSS_CHORDS, BOSS_MELODY, {
        "key": 50,
        "lead_wave": "pulse", "lead_duty": 0.35, "lead_cutoff": 2800.0, "lead_vol": 0.20, "vibrato": 0.004,
        "arp_wave": "pulse", "arp_step": 1, "arp_octave": 0, "arp_vol": 0.045, "arp_cutoff": 1800.0,
        "pad_vol": 0.04, "pad_octave": 0, "pad_cutoff": 650.0,
        "bass_wave": "pulse", "bass_cutoff": 800.0, "bass_vol": 0.3, "bass_sub": 0.6, "bass_octave": -24, "bass_len": 0.9,
        "bass_pattern": [(k, 12 if k % 4 == 2 else 0) for k in range(0, 16)],
        "kicks": (0, 4, 8, 10, 12), "snares": (4, 12), "hats": tuple(range(1, 16, 2)),
        "kick_vol": 0.85, "snare_vol": 0.45, "hat_vol": 0.08, "echo": 0.18,
    })


def legacy_village():
    return render("village", 92, VILLAGE_CHORDS, VILLAGE_MELODY, {
        "key": 60,
        "lead_wave": "triangle", "lead_cutoff": 2400.0, "lead_vol": 0.36, "vibrato": 0.006, "lead_attack": 0.03,
        "arp_wave": "triangle", "arp_step": 2, "arp_octave": -12, "arp_vol": 0.13, "arp_cutoff": 1800.0, "arp_up": False,
        "pad_vol": 0.03, "pad_octave": 0, "pad_cutoff": 600.0,
        "bass_wave": "triangle", "bass_cutoff": 900.0, "bass_vol": 0.4, "bass_octave": -24, "bass_len": 3.6,
        "bass_pattern": [(0, 0), (8, 7)],
        "kicks": (0,), "snares": (), "hats": (4, 12),
        "kick_vol": 0.25, "snare_vol": 0.0, "hat_vol": 0.04, "echo": 0.3,
    })


# =================================================================== synthesis engine (D-092)

def seeded(*key):
    """Deterministic RNG for one sound (str hashes are salted per process, crc32 is not)."""
    return random.Random(zlib.crc32(repr(key).encode()))


def mix_into(buf, start, samples, gain):
    """Adds samples * gain into buf at start, wrapping around the loop end."""
    n = len(buf)
    m = len(samples)
    start %= n
    i = 0
    while i < m:
        take = min(m - i, n - start)
        segment = samples[i:i + take]
        buf[start:start + take] = [a + b * gain for a, b in zip(buf[start:start + take], segment)]
        i += take
        start = 0


class Inst:
    """One instrument: oscillator(s) -> one/two-pole low-pass -> envelope. Rendered notes are cached.

    wave: pulse, saw, triangle, sine, organ (integer harmonics), fm (sine with a decaying
    modulator) or partials (additive bell/mallet, each partial with its own decay)."""

    def __init__(self, sr, wave="pulse", duty=0.5, cutoff=3000.0, poles=1, attack=0.01, decay=0.2,
                 sustain=0.6, release=0.08, perc=0.0, vibrato=0.0, vib_rate=5.0, vib_delay=0.12,
                 sub=0.0, detune=0.0, glide=0.0, glide_time=0.04, harmonics=None, partials=None,
                 fm_ratio=2.0, fm_index=0.0, fm_decay=0.3, trem=0.0, trem_rate=5.0,
                 filter_env=0.0, filter_decay=0.12, noise=0.0):
        self.sr = sr
        self.wave = wave
        self.duty = duty
        self.cutoff = min(cutoff, 0.45 * sr)
        self.poles = poles
        self.attack = attack
        self.decay = decay
        self.sustain = sustain
        self.release = release
        self.perc = perc
        self.vibrato = vibrato
        self.vib_rate = vib_rate
        self.vib_delay = vib_delay
        self.sub = sub
        self.detune = detune
        self.glide = glide
        self.glide_time = glide_time
        total = sum(a for _, a in harmonics) if harmonics else 1.0
        self.harmonics = [(r, a / total) for r, a in harmonics] if harmonics else []
        self.partials = partials or []
        self.fm_ratio = fm_ratio
        self.fm_index = fm_index
        self.fm_decay = fm_decay
        self.trem = trem
        self.trem_rate = trem_rate
        self.filter_env = filter_env
        self.filter_decay = filter_decay
        self.noise = noise
        self._cache = {}

    def render(self, note, n_on):
        key = (note, n_on)
        cached = self._cache.get(key)
        if cached is None:
            if self.wave == "partials":
                cached = self._render_partials(midi_freq(note), n_on)
            else:
                cached = self._render(midi_freq(note), n_on)
            self._cache[key] = cached
        return cached

    def _render(self, freq, n_on):
        sr = self.sr
        r_n = max(1, int(self.release * sr))
        n = n_on + r_n
        out = [0.0] * n
        a_n = max(1, int(self.attack * sr))
        d_n = max(1, int(self.decay * sr))
        sus = self.sustain
        perc_k = math.exp(-1.0 / (self.perc * sr)) if self.perc > 0.0 else 0.0
        env_p = 1.0
        wave = self.wave
        duty = self.duty
        harmonics = self.harmonics
        cutoff = self.cutoff
        alpha = 1.0 - math.exp(-TAU * cutoff / sr)
        fenv = self.filter_env
        fenv_k = math.exp(-16.0 / (self.filter_decay * sr)) if fenv else 0.0
        glide_off = 2.0 ** (self.glide / 12.0) - 1.0 if self.glide else 0.0
        glide_k = math.exp(-1.0 / (self.glide_time * sr)) if self.glide else 0.0
        vib = self.vibrato
        vib_w = TAU * self.vib_rate / sr
        vib_start = int(self.vib_delay * sr)
        trem = self.trem
        trem_w = TAU * self.trem_rate / sr
        det = 2.0 ** (self.detune / 1200.0) if self.detune else 0.0
        fm_cur = self.fm_index
        fm_ratio = self.fm_ratio
        fm_k = math.exp(-1.0 / (self.fm_decay * sr)) if self.fm_index else 1.0
        noise = self.noise
        rng = seeded("inst", freq, n_on, noise) if noise else None
        sub = self.sub
        two_pole = self.poles == 2
        sin = math.sin
        base_dt = freq / sr
        phase = phase2 = sub_phase = mod_phase = 0.0
        lp1 = lp2 = 0.0
        for i in range(n):
            if i < a_n:
                env = i / a_n
            elif perc_k:
                env_p *= perc_k
                env = env_p
            elif i < a_n + d_n:
                env = 1.0 - (1.0 - sus) * (i - a_n) / d_n
            else:
                env = sus
            if i >= n_on:
                env *= 1.0 - (i - n_on) / r_n
            dt = base_dt
            if glide_off:
                glide_off *= glide_k
                dt *= 1.0 + glide_off
            if vib and i > vib_start:
                dt *= 1.0 + vib * sin(vib_w * i)
            phase += dt
            if phase >= 1.0:
                phase -= 1.0
            if wave == "pulse":
                v = (1.0 if phase < duty else -1.0) + polyblep(phase, dt) - polyblep((phase - duty) % 1.0, dt)
            elif wave == "saw":
                v = 2.0 * phase - 1.0 - polyblep(phase, dt)
            elif wave == "triangle":
                v = 4.0 * phase - 1.0 if phase < 0.5 else 3.0 - 4.0 * phase
            elif wave == "organ":
                v = 0.0
                for ratio, amp in harmonics:
                    v += amp * sin(TAU * ratio * phase)
            elif wave == "fm":
                mod_phase += dt * fm_ratio
                if mod_phase >= 1.0:
                    mod_phase -= 1.0
                v = sin(TAU * phase + fm_cur * sin(TAU * mod_phase))
                fm_cur *= fm_k
            else:
                v = sin(TAU * phase)
            if det:
                dt2 = dt * det
                phase2 += dt2
                if phase2 >= 1.0:
                    phase2 -= 1.0
                if wave == "saw":
                    v2 = 2.0 * phase2 - 1.0 - polyblep(phase2, dt2)
                elif wave == "pulse":
                    v2 = (1.0 if phase2 < duty else -1.0) + polyblep(phase2, dt2) - polyblep((phase2 - duty) % 1.0, dt2)
                elif wave == "triangle":
                    v2 = 4.0 * phase2 - 1.0 if phase2 < 0.5 else 3.0 - 4.0 * phase2
                else:
                    v2 = sin(TAU * phase2)
                v = 0.5 * (v + v2)
            if sub:
                sub_phase += dt * 0.5
                if sub_phase >= 1.0:
                    sub_phase -= 1.0
                v += sub * sin(TAU * sub_phase)
            if noise:
                v += noise * (rng.random() * 2.0 - 1.0)
            if fenv and (i & 15) == 0:
                c = min(cutoff * (1.0 + fenv), 0.45 * sr)
                alpha = 1.0 - math.exp(-TAU * c / sr)
                fenv *= fenv_k
            lp1 += alpha * (v - lp1)
            if two_pole:
                lp2 += alpha * (lp1 - lp2)
                y = lp2
            else:
                y = lp1
            if trem:
                y *= 1.0 - trem * (0.5 + 0.5 * sin(trem_w * i))
            out[i] = y * env
        return out

    def _render_partials(self, freq, n_on):
        sr = self.sr
        r_n = max(1, int(self.release * sr))
        n = n_on + r_n
        out = [0.0] * n
        total = sum(a for _, a, _ in self.partials) or 1.0
        for ratio, amp, decay in self.partials:
            f = freq * ratio
            if f >= 0.45 * sr:
                continue
            w = TAU * f / sr
            c2 = 2.0 * math.cos(w)
            s_prev = -math.sin(w)
            s_cur = 0.0
            k = math.exp(-1.0 / (decay * sr))
            e = amp / total
            for i in range(n):
                out[i] += s_cur * e
                s_prev, s_cur = s_cur, c2 * s_cur - s_prev
                e *= k
        a_n = max(1, int(self.attack * sr))
        for i in range(min(a_n, n)):
            out[i] *= i / a_n
        for i in range(n_on, n):
            out[i] *= 1.0 - (i - n_on) / r_n
        return out


# Additive partials (ratio, amplitude, decay in s) relative to the played (nominal) pitch.
BELL_PARTIALS = ((0.25, 0.5, 3.2), (0.5, 0.7, 2.4), (0.6, 0.45, 1.8), (0.75, 0.3, 1.4),
                 (1.0, 1.0, 1.2), (1.25, 0.2, 0.6), (1.5, 0.25, 0.5), (2.0, 0.12, 0.3))
SMALL_BELL_PARTIALS = ((1.0, 1.0, 0.9), (2.0, 0.35, 0.4), (2.4, 0.3, 0.3), (3.0, 0.15, 0.2), (4.2, 0.08, 0.12))
MALLET_PARTIALS = ((1.0, 1.0, 0.32), (3.93, 0.28, 0.07), (9.2, 0.07, 0.02))
CELESTA_PARTIALS = ((1.0, 1.0, 0.8), (2.0, 0.3, 0.3), (3.0, 0.12, 0.15), (4.16, 0.06, 0.08))


# --------------------------------------------------------------- percussion and textures

_HIT_CACHE = {}


def hit(kind, sr, variant=0, **params):
    """One percussion/texture hit, cached per (kind, parameters, variant)."""
    key = (kind, sr, variant, tuple(sorted(params.items())))
    samples = _HIT_CACHE.get(key)
    if samples is None:
        samples = HITS[kind](sr, seeded(key), **params)
        _HIT_CACHE[key] = samples
    return samples


def _kick(sr, rng, f0=45.0, f1=110.0, sweep=28.0, decay=14.0, length=0.22, click=0.0):
    n = int(length * sr)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / sr
        phase += (f0 + f1 * math.exp(-t * sweep)) / sr
        out[i] = math.sin(TAU * phase) * math.exp(-t * decay)
    for i in range(min(n, int(0.003 * sr))):
        out[i] += click * (rng.random() * 2.0 - 1.0) * (1.0 - i / (0.003 * sr))
    return out


def _snare(sr, rng, tone=190.0, decay=18.0, length=0.18, bright=0.45, body=0.5):
    n = int(length * sr)
    out = [0.0] * n
    lp = 0.0
    phase = 0.0
    for i in range(n):
        t = i / sr
        lp += bright * (rng.random() * 2.0 - 1.0 - lp)
        phase += tone / sr
        out[i] = lp * math.exp(-t * decay) + math.sin(TAU * phase) * math.exp(-t * 30.0) * body
    return out


def _hat(sr, rng, length=0.035):
    n = max(2, int(length * sr))
    out = [0.0] * n
    last = 0.0
    for i in range(n):
        x = rng.random() * 2.0 - 1.0
        out[i] = (x - last) * math.exp(-i / (n * 0.35))
        last = x
    return out


def _shaker(sr, rng, length=0.07):
    n = int(length * sr)
    out = [0.0] * n
    last = 0.0
    a_n = max(1, int(0.012 * sr))
    for i in range(n):
        x = rng.random() * 2.0 - 1.0
        env = i / a_n if i < a_n else math.exp(-(i - a_n) / (0.02 * sr))
        out[i] = (x - last) * 0.6 * env
        last = x
    return out


def _tom(sr, rng, freq=110.0, length=0.45, decay=7.0, noise=0.15, bend=0.6):
    n = int(length * sr)
    out = [0.0] * n
    phase = 0.0
    lp = 0.0
    for i in range(n):
        t = i / sr
        phase += freq * (1.0 + bend * math.exp(-t * 30.0)) / sr
        v = math.sin(TAU * phase) + 0.25 * math.sin(TAU * phase * 1.5)
        lp += 0.2 * (rng.random() * 2.0 - 1.0 - lp)
        out[i] = v * math.exp(-t * decay) + lp * noise * math.exp(-t * 40.0)
    return out


def _taiko(sr, rng, freq=62.0):
    out = _tom(sr, rng, freq, 0.9, 4.5, 0.6, 0.9)
    for i in range(int(0.004 * sr)):
        out[i] += (rng.random() * 2.0 - 1.0) * 0.5
    return out


def _anvil(sr, rng, freq=1650.0, decay=0.45):
    n = int(decay * 2.5 * sr)
    partials = ((1.0, 1.0, decay), (1.006, 0.45, decay), (2.76, 0.5, decay * 0.45),
                (5.40, 0.3, decay * 0.25), (8.93, 0.15, decay * 0.12))
    out = [0.0] * n
    for ratio, amp, d in partials:
        w = TAU * freq * ratio / sr
        if freq * ratio >= 0.45 * sr:
            continue
        k = math.exp(-1.0 / (d * sr))
        e = amp * 0.4
        for i in range(n):
            out[i] += math.sin(w * i) * e
            e *= k
    last = 0.0
    for i in range(int(0.004 * sr)):
        x = rng.random() * 2.0 - 1.0
        out[i] += (x - last) * 0.6
        last = x
    return out


def _drip(sr, rng, freq=1300.0, length=0.13):
    n = int(length * sr)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / sr
        phase += freq * (1.0 + 0.9 * (1.0 - math.exp(-t / 0.012))) / sr
        env = min(1.0, t / 0.001) * math.exp(-t * 38.0)
        out[i] = math.sin(TAU * phase) * env
    return out


def _bloop(sr, rng, freq=220.0, length=0.14, rise=1.0):
    n = int(length * sr)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / sr
        phase += freq * (1.0 + rise * t / length) / sr
        env = min(1.0, t / 0.006) * math.exp(-t * 22.0)
        out[i] = math.sin(TAU * phase) * env
    return out


def _boom(sr, rng, freq=42.0, length=1.6):
    n = int(length * sr)
    out = [0.0] * n
    phase = 0.0
    lp = lp2 = 0.0
    a = 1.0 - math.exp(-TAU * 140.0 / sr)
    for i in range(n):
        t = i / sr
        phase += freq * (1.0 + 0.5 * math.exp(-t * 18.0)) / sr
        lp += a * (rng.random() * 2.0 - 1.0 - lp)
        lp2 += a * (lp - lp2)
        out[i] = (math.sin(TAU * phase) + lp2 * 1.5) * math.exp(-t * 2.6) * min(1.0, t / 0.004)
    return out


def _swell(sr, rng, length=2.0, top=5000.0):
    """Reverse-cymbal: noise rising in level and brightness, cut at the end."""
    n = int(length * sr)
    out = [0.0] * n
    lp = 0.0
    for i in range(n):
        x = i / n
        a = 1.0 - math.exp(-TAU * (200.0 + top * x * x) / sr)
        lp += a * (rng.random() * 2.0 - 1.0 - lp)
        tail = min(1.0, (n - i) / (0.01 * sr))
        out[i] = lp * x * x * x * tail
    return out


def _clink(sr, rng, freq=2600.0):
    n = int(0.25 * sr)
    out = [0.0] * n
    for ratio, amp, d in ((1.0, 1.0, 0.12), (1.47, 0.6, 0.08), (2.09, 0.4, 0.05), (2.56, 0.3, 0.04)):
        f = freq * ratio * (1.0 + (rng.random() - 0.5) * 0.06)
        if f >= 0.45 * sr:
            continue
        w = TAU * f / sr
        k = math.exp(-1.0 / (d * sr))
        e = amp
        for i in range(n):
            out[i] += math.sin(w * i) * e * 0.4
            e *= k
    return out


def _crackle(sr, rng, length=0.004, tone=0.55):
    n = max(4, int(length * sr))
    out = [0.0] * n
    last = 0.0
    lp = 0.0
    for i in range(n):
        x = rng.random() * 2.0 - 1.0
        lp += tone * ((x - last) - lp)
        last = x
        out[i] = lp * math.exp(-i / (n * 0.3))
    return out


def _chirp(sr, rng, f0=3200.0, f1=4200.0, length=0.08, harm=0.12):
    n = int(length * sr)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        x = i / n
        phase += (f0 + (f1 - f0) * x) / sr
        env = math.sin(math.pi * x) ** 2
        out[i] = (math.sin(TAU * phase) + harm * math.sin(2.0 * TAU * phase)) * env
    return out


# Vowel formants (Hz) for the whisper texture.
FORMANTS = ((700, 1200), (400, 2000), (300, 2300), (500, 900), (350, 800), (600, 1700))


def _whisper(sr, rng, length=1.6):
    """Breathy noise in syllables through two formant band-passes plus a few sibilants."""
    n = int(length * sr)
    out = [0.0] * n
    pos = 0
    while pos < n:
        syl = int((0.12 + rng.random() * 0.16) * sr)
        f1, f2 = FORMANTS[rng.randrange(len(FORMANTS))]
        noise = [rng.random() * 2.0 - 1.0 for _ in range(syl)]
        band = [a + 0.7 * b for a, b in zip(biquad(noise, "bp", f1 * 1.3, 4.0, sr), biquad(noise, "bp", f2 * 1.2, 5.0, sr))]
        if rng.random() < 0.3:
            hiss = biquad(noise, "hp", 4500.0, 0.7, sr)
            band = [a + 0.5 * b for a, b in zip(band, hiss)]
        for i in range(syl):
            if pos + i >= n:
                break
            x = i / syl
            out[pos + i] += band[i] * math.sin(math.pi * x) ** 1.5
        pos += syl + int(rng.random() * 0.05 * sr)
    for i in range(n):  # phrase envelope
        x = i / n
        out[i] *= min(1.0, x / 0.15) * min(1.0, (1.0 - x) / 0.25)
    return out


HITS = {
    "kick": _kick, "snare": _snare, "hat": _hat, "shaker": _shaker, "tom": _tom, "taiko": _taiko,
    "anvil": _anvil, "drip": _drip, "bloop": _bloop, "boom": _boom, "swell": _swell,
    "clink": _clink, "crackle": _crackle, "chirp": _chirp, "whisper": _whisper,
}


# --------------------------------------------------------------- filters and effects

def biquad(buf, kind, freq, q, sr, circular=False):
    """RBJ low/high/band-pass. circular=True filters a loop seamlessly (two passes)."""
    w0 = TAU * min(freq, 0.45 * sr) / sr
    cw = math.cos(w0)
    alpha = math.sin(w0) / (2.0 * q)
    if kind == "lp":
        b0, b1, b2 = (1.0 - cw) / 2.0, 1.0 - cw, (1.0 - cw) / 2.0
    elif kind == "hp":
        b0, b1, b2 = (1.0 + cw) / 2.0, -(1.0 + cw), (1.0 + cw) / 2.0
    else:
        b0, b1, b2 = alpha, 0.0, -alpha
    a0 = 1.0 + alpha
    b0, b1, b2 = b0 / a0, b1 / a0, b2 / a0
    a1, a2 = -2.0 * cw / a0, (1.0 - alpha) / a0
    out = [0.0] * len(buf)
    x1 = x2 = y1 = y2 = 0.0
    for _ in range(2 if circular else 1):
        for i, x in enumerate(buf):
            y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1, y2, y1 = x1, x, y1, y
            out[i] = y
    return out


def one_pole_hp(buf, cutoff, sr):
    """Circular one-pole high-pass (DC removal / loudness weighting)."""
    a = math.exp(-TAU * cutoff / sr)
    out = [0.0] * len(buf)
    prev = y = 0.0
    for _ in range(2):
        for i, x in enumerate(buf):
            y = a * (y + x - prev)
            prev = x
            out[i] = y
    return out


def _comb(buf, delay, feedback, damp):
    n = len(buf)
    out = [0.0] * n
    line = [0.0] * delay
    pos = 0
    lp = 0.0
    keep = 1.0 - damp
    for _ in range(2):
        for i in range(n):
            y = line[pos]
            lp = y * keep + lp * damp
            line[pos] = buf[i] + lp * feedback
            pos += 1
            if pos == delay:
                pos = 0
            out[i] = y
    return out


def _allpass(buf, delay, g=0.6):
    n = len(buf)
    out = [0.0] * n
    line = [0.0] * delay
    pos = 0
    for _ in range(2):
        for i in range(n):
            delayed = line[pos]
            x = buf[i] + delayed * g
            line[pos] = x
            pos += 1
            if pos == delay:
                pos = 0
            out[i] = delayed - x * g
    return out


def reverb(buf, sr, size=1.0, feedback=0.8, damp=0.3):
    """Schroeder hall (4 combs, 2 all-passes) that wraps around the loop. Returns the wet signal."""
    wet = [0.0] * len(buf)
    for d in (0.0297, 0.0371, 0.0411, 0.0437):
        c = _comb(buf, max(2, int(d * size * sr)), feedback, damp)
        wet = [a + b for a, b in zip(wet, c)]
    for d in (0.0050, 0.0017):
        wet = _allpass(wet, max(2, int(d * size * sr)))
    return [v * 0.25 for v in wet]


def soft_limit(buf, ceiling=CEILING, knee=0.6):
    k = ceiling * knee
    span = ceiling - k
    out = []
    for v in buf:
        a = abs(v)
        if a > k:
            a = k + span * math.tanh((a - k) / span)
            v = a if v > 0.0 else -a
        out.append(v)
    return out


def loudness_db(buf, sr):
    hp = one_pole_hp(buf, 150.0, sr)
    return 20.0 * math.log10(max(1e-9, math.sqrt(sum(v * v for v in hp) / len(hp))))


def stats(buf, sr):
    """(seconds, peak dBFS, RMS dBFS, loudness dB, seam jump / 99.9 % of all sample steps)."""
    peak = max(1e-9, max(abs(v) for v in buf))
    rms = math.sqrt(sum(v * v for v in buf) / len(buf))
    steps = sorted(abs(buf[i] - buf[i - 1]) for i in range(1, len(buf)))
    typical = max(1e-9, steps[int(len(steps) * 0.999)])
    seam = abs(buf[0] - buf[-1]) / typical
    return len(buf) / sr, 20.0 * math.log10(peak), 20.0 * math.log10(max(1e-9, rms)), loudness_db(buf, sr), seam


def finish(name, out_dir, sr, layers, target_db):
    """Sums the layers, removes DC, matches the loudness target under a soft limiter, writes."""
    mixed = [0.0] * len(layers[0])
    for layer in layers:
        mixed = [a + b for a, b in zip(mixed, layer)]
    mixed = one_pole_hp(mixed, 18.0, sr)
    for _ in range(4):
        gain = 10.0 ** ((target_db - loudness_db(mixed, sr)) / 20.0)
        mixed = soft_limit([v * gain for v in mixed])
        if abs(gain - 1.0) < 0.01:
            break
    out_dir.mkdir(parents=True, exist_ok=True)
    data = array("h", (int(max(-1.0, min(1.0, v)) * 32767) for v in mixed))
    with wave.open(str(out_dir / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data.tobytes())
    seconds, peak, rms, loud, seam = stats(mixed, sr)
    return f"{name}: {seconds:.1f} s, peak {peak:.1f} dBFS, RMS {rms:.1f} dBFS, loudness {loud:.1f} dB, seam {seam:.2f}"


# --------------------------------------------------------------- notation

NOTE_PC = {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}
CHORD_INTERVALS = {
    "": (0, 4, 7), "m": (0, 3, 7), "dim": (0, 3, 6), "5": (0, 7, 12), "sus2": (0, 2, 7),
    "sus4": (0, 5, 7), "7": (0, 4, 7, 10), "m7": (0, 3, 7, 10), "maj7": (0, 4, 7, 11),
    "add9": (0, 4, 7, 14), "madd9": (0, 3, 7, 14), "m9": (0, 3, 7, 10, 14),
}


def parse_note(token):
    """'c#5', 'bb4', 'a3' -> MIDI note number (C4 = 60)."""
    token = token.lower()
    pc = NOTE_PC[token[0]]
    i = 1
    while token[i] in "#b":
        pc += 1 if token[i] == "#" else -1
        i += 1
    return 12 * (int(token[i:]) + 1) + pc


def parse_melody(text):
    """'d5:6 c5:2 a4:8 | ...' (lengths in 16ths, 'r' = rest) -> bars of (note, steps)."""
    bars = []
    for bar_text in text.split("|"):
        events = []
        total = 0.0
        for token in bar_text.split():
            name, length = token.split(":")
            events.append((None if name == "r" else parse_note(name), float(length)))
            total += float(length)
        if abs(total - 16.0) > 1e-6:
            raise ValueError(f"bar has {total} steps instead of 16: {bar_text.strip()}")
        bars.append(events)
    return bars


def parse_chord(token):
    """'F#m', 'Bb', 'Gmaj7' -> (pitch class, intervals)."""
    pc = NOTE_PC[token[0].lower()]
    i = 1
    if i < len(token) and token[i] in "#b":
        pc += 1 if token[i] == "#" else -1
        i += 1
    return pc % 12, CHORD_INTERVALS[token[i:]]


def parse_chords(text):
    """'Dm | Bb | Gm A' -> one list per bar (two chords = half a bar each)."""
    return [[parse_chord(t) for t in bar.split()] for bar in text.split("|")]


def chord_at(chords, bar, step=0):
    bar_chords = chords[bar % len(chords)]
    return bar_chords[0] if len(bar_chords) == 1 or step < 8 else bar_chords[1]


def voice(chord_spec, low):
    """Chord tones, root at the first note >= low."""
    pc, intervals = chord_spec
    root = low + (pc - low) % 12
    return [root + i for i in intervals]


def root_of(chord_spec, low):
    return low + (chord_spec[0] - low) % 12


LEVELS = {"X": 1.0, "x": 0.75, "o": 0.5, "-": 0.3}


class Song:
    """A loop of whole bars (16 steps each); every layer is one buffer of the loop length."""

    def __init__(self, bpm, bars, sr=MUSIC_SR, swing=0.0):
        self.sr = sr
        self.bpm = bpm
        self.bars = bars
        self.step = int(round(60.0 / bpm / 4.0 * sr))  # integer samples per 16th: exact bar grid
        self.length = bars * 16 * self.step
        self.swing = swing
        self.layers = {}

    def buf(self, name):
        if name not in self.layers:
            self.layers[name] = [0.0] * self.length
        return self.layers[name]

    def pos(self, bar, step):
        s = bar * 16 + step
        if self.swing and abs(step % 4 - 2.0) < 1e-6:
            s += self.swing
        return int(round(s * self.step))

    def add(self, layer, samples, bar, step, gain):
        mix_into(self.buf(layer), self.pos(bar, step), samples, gain)

    def note(self, layer, inst, bar, step, steps, note, vol, gate=0.95):
        if note is None or vol <= 0.0:
            return
        self.add(layer, inst.render(note, int(steps * self.step * gate)), bar, step, vol)

    def melody(self, layer, inst, first_bar, bars, vol, transpose=0, gate=0.95):
        for b, events in enumerate(bars):
            step = 0.0
            for note, length in events:
                if note is not None:
                    self.note(layer, inst, first_bar + b, step, length, note + transpose, vol, gate)
                step += length

    def drums(self, layer, bar, pattern, sound, vol):
        """pattern: 'X..x o...' (X 1.0, x 0.75, o 0.5, - 0.3, . none); may span several bars.
        sound: samples or a function step -> samples."""
        for k, ch in enumerate(pattern.replace(" ", "").replace("|", "")):
            level = LEVELS.get(ch)
            if level:
                samples = sound(k) if callable(sound) else sound
                self.add(layer, samples, bar + k // 16, k % 16, vol * level)

    def pad(self, layer, inst, chords, bars, low, vol):
        for bar in bars:
            bar_chords = chords[bar % len(chords)]
            span = 16 // len(bar_chords)
            for c_index, spec in enumerate(bar_chords):
                for note in voice(spec, low):
                    self.note(layer, inst, bar, c_index * span, span, note, vol, 1.0)

    def bass(self, layer, inst, chords, bars, pattern, low, vol):
        """pattern: (step, semitones above the root, length in steps)."""
        for bar in bars:
            for step, offset, length in pattern:
                root = root_of(chord_at(chords, bar, step), low)
                self.note(layer, inst, bar, step, length, root + offset, vol)

    def arp(self, layer, inst, chords, bars, low, order, every, vol, gate=0.9):
        """Broken chords: order indexes [chord tones..., root + 12], one note per `every` steps."""
        index = 0
        for bar in bars:
            for k in range(0, 16, every):
                tones = voice(chord_at(chords, bar, k), low)
                tones = tones + [tones[0] + 12]
                note = tones[order[index % len(order)] % len(tones)]
                self.note(layer, inst, bar, k, every, note, vol, gate)
                index += 1

    def mix(self, sends, reverb_args=None, wet=0.4, echoes=None):
        """Returns all layers plus one reverb return. sends: layer -> reverb send amount,
        echoes: layer -> (delay steps, feedback, mix) applied before the reverb."""
        layers = dict(self.layers)
        for name, (steps, feedback, amount) in (echoes or {}).items():
            if name in layers:
                layers[name] = echo(layers[name], int(steps * self.step), feedback, amount)
        out = list(layers.values())
        if reverb_args is not None:
            send = [0.0] * self.length
            for name, amount in sends.items():
                if name in layers and amount > 0.0:
                    send = [a + b * amount for a, b in zip(send, layers[name])]
            out.append([v * wet for v in reverb(send, self.sr, **reverb_args)])
        return out


def bars_of(*ranges):
    result = []
    for start, end in ranges:
        result.extend(range(start, end))
    return result


# =================================================================== biome tracks (D-092)
# Each biome function renders the base loop or, with intense=True, the champion version with
# the same tempo and bars (MusicPlayer crossfades between both at the same position).

CRYPT = {"bpm": 84, "key": "D minor", "bars": 24}
CRYPT_CHORDS = parse_chords("Dm | Bb | Gm | A | Dm | F | Gm A | Dm | "
                            "F | C | Dm | Bb | Gm | C | A | A | "
                            "Dm | Bb | Gm | A | Dm | F | Gm | A")
CRYPT_A = parse_melody("d5:6 c5:2 a4:8 | bb4:4 a4:4 g4:4 f4:4 | g4:6 a4:2 bb4:4 d5:4 | c#5:8 a4:8 | "
                       "d5:6 e5:2 f5:4 e5:4 | c5:6 d5:2 a4:8 | bb4:4 g4:4 a4:4 c#5:4 | d5:12 r:4")
CRYPT_B = parse_melody("f5:4 e5:2 d5:2 c5:4 a4:4 | g4:4 c5:4 e5:6 d5:2 | f5:6 e5:2 d5:4 a4:4 | bb4:8 d5:4 f5:4 | "
                       "g5:6 f5:2 e5:4 d5:4 | e5:4 c5:4 g4:4 c5:4 | c#5:6 d5:2 e5:4 a4:4 | a4:12 r:4")
CRYPT_A_END = parse_melody("bb4:4 g4:4 bb4:4 d5:4 | e5:4 c#5:4 a4:4 e4:4")


def song_crypt(intense=False):
    """Crypt: slow funeral march, drawbar organ, church bells, harpsichord, timpani, stone hall."""
    song = Song(CRYPT["bpm"], CRYPT["bars"])
    sr = song.sr
    bright = 1.3 if intense else 1.0
    chords = CRYPT_CHORDS
    organ_lead = Inst(sr, "organ", harmonics=((1, 1.0), (2, 0.55), (3, 0.3), (4, 0.2), (6, 0.08)),
                      cutoff=2200 * bright, attack=0.03, decay=0.3, sustain=0.8, release=0.25, trem=0.12, trem_rate=5.6)
    organ_pad = Inst(sr, "organ", harmonics=((1, 1.0), (2, 0.6), (4, 0.25)), sub=0.3, cutoff=1100 * bright,
                     attack=0.4, decay=0.5, sustain=0.85, release=0.7, trem=0.07, trem_rate=5.2)
    pedal = Inst(sr, "organ", harmonics=((1, 1.0), (2, 0.4), (3, 0.1)), cutoff=500, attack=0.08, sustain=0.9, release=0.35)
    celesta = Inst(sr, "partials", partials=CELESTA_PARTIALS, attack=0.002, release=0.3)
    harpsichord = Inst(sr, "pulse", duty=0.22, cutoff=2800 * bright, attack=0.002, perc=0.16, release=0.06)
    bell = Inst(sr, "partials", partials=BELL_PARTIALS, attack=0.002, release=0.8)

    song.pad("pad", organ_pad, chords, range(24), 50, 0.06)
    still = [(0, 0, 16)]
    walking = [(0, 0, 8), (8, 0, 6), (14, 7, 2)]
    song.bass("pedal", pedal, chords, range(8), still, 33, 0.3)
    song.bass("pedal", pedal, chords, range(8, 24), walking, 33, 0.3)

    song.melody("lead", organ_lead, 0, CRYPT_A, 0.16)
    song.melody("lead", organ_lead, 8, CRYPT_B, 0.09)
    song.melody("celesta", celesta, 8, CRYPT_B, 0.26)
    song.melody("lead", organ_lead, 16, CRYPT_A[:6] + CRYPT_A_END, 0.16)
    song.melody("celesta", celesta, 16, CRYPT_A[:6] + CRYPT_A_END, 0.1, transpose=12)

    arp_bars = range(24) if intense else range(8, 24)
    song.arp("harps", harpsichord, chords, arp_bars, 62, [0, 2, 1, 2, 3, 2, 1, 2], 1 if intense else 2,
             0.045 if intense else 0.055)

    for bar in (0, 8, 16):
        song.note("bells", bell, bar, 0, 32, root_of(chord_at(chords, bar), 62), 0.22)
    for bar in (4, 12, 20):
        song.note("bells", bell, bar, 0, 32, root_of(chord_at(chords, bar), 62) + 7, 0.14)
    for bar in range(17, 24, 2):
        song.note("bells", bell, bar, 8, 16, root_of(chord_at(chords, bar), 74), 0.07)

    def timpani(bar):
        return hit("tom", sr, 0, freq=round(midi_freq(root_of(chord_at(chords, bar), 38)), 1), length=0.7, decay=5.0, noise=0.25)

    for bar in range(24):
        pattern = "X.......x......." if bar < 8 else "X.......x.....o."
        song.drums("timp", bar, pattern, timpani(bar), 0.42)
        if bar >= 16:
            song.drums("drums", bar, "..o...o...o...o.", lambda k: hit("shaker", sr, k % 3), 0.1)
    if intense:
        for bar in range(24):
            song.drums("drums", bar, "X......xX.......", hit("kick", sr, 0, f0=40.0, decay=10.0), 0.55)
            song.drums("drums", bar, "....x.......x...", hit("snare", sr, 0, tone=160.0, decay=14.0), 0.22)
            song.drums("drums", bar, "o.o.o.o.o.o.o.o.", lambda k: hit("shaker", sr, k % 4), 0.08)
            if bar % 4 == 3:
                for k, f in ((12, 180.0), (13, 150.0), (14, 120.0), (15, 95.0)):
                    song.drums("drums", bar, "." * k + "x", hit("tom", sr, 1, freq=f), 0.3)

    return song.mix({"pad": 0.45, "lead": 0.35, "celesta": 0.55, "bells": 0.6, "harps": 0.3, "timp": 0.35, "drums": 0.2},
                    {"size": 1.25, "feedback": 0.83, "damp": 0.42}, wet=0.55, echoes={"lead": (3, 0.25, 0.18)})


SLIME = {"bpm": 104, "key": "E minor", "bars": 32}
SLIME_CHORDS = parse_chords("Em | Em | Am | B | Em | C | Am B | Em | "
                            "C | D | Bm | Em | C | D | B | B | "
                            "Em | Em | Am | B | Em | C | Am B | Em | "
                            "Em | F | Em | F | C | B | Em | B")
SLIME_A = parse_melody("e5:2 r:1 g5:1 b5:2 g5:2 f#5:2 e5:2 d#5:2 e5:2 | b4:2 r:2 b4:1 c5:1 b4:2 a4:2 g4:2 f#4:2 g4:2 | "
                       "a4:2 r:1 c5:1 e5:2 c5:2 a5:4 g5:2 e5:2 | f#5:2 d#5:2 b4:2 d#5:2 f#5:4 r:4 | "
                       "e5:2 r:1 g5:1 b5:2 g5:2 e6:4 d6:2 b5:2 | c6:2 b5:2 g5:2 e5:2 g5:4 r:2 e5:2 | "
                       "a5:2 g5:2 f#5:2 e5:2 d#5:2 f#5:2 b4:4 | e5:8 r:8")
SLIME_B = parse_melody("g4:4 e4:2 g4:2 c5:4 b4:4 | a4:4 f#4:2 a4:2 d5:4 c5:4 | b4:2 d5:2 f#5:4 e5:2 d5:2 b4:4 | "
                       "e5:6 f#5:2 g5:4 e5:4 | c5:2 e5:2 g5:2 c6:2 b5:4 g5:4 | a5:2 f#5:2 d5:2 a5:2 c6:4 a5:4 | "
                       "b5:4 a5:2 g5:2 f#5:4 d#5:4 | f#5:8 d#5:4 b4:4")
SLIME_C = parse_melody("r:8 b4:2 c5:2 b4:4 | r:8 c5:2 b4:2 a4:4 | r:8 g4:2 a4:2 b4:4 | c5:4 b4:4 a4:4 f4:4 | "
                       "e5:4 g5:4 c6:4 g5:4 | f#5:4 d#5:4 b4:4 a4:4 | g4:4 b4:4 e5:4 g5:4 | f#5:6 e5:2 d#5:4 b4:4")


def song_slime_grotto(intense=False):
    """Slime grotto: swung and bouncy, marimba, gliding bloop bass, tuned drips, wet cave."""
    song = Song(SLIME["bpm"], SLIME["bars"], swing=0.33)
    sr = song.sr
    bright = 1.3 if intense else 1.0
    chords = SLIME_CHORDS
    mallet = Inst(sr, "partials", partials=MALLET_PARTIALS, attack=0.002, release=0.12)
    plink = Inst(sr, "pulse", duty=0.125, cutoff=2000 * bright, attack=0.002, perc=0.09, release=0.05)
    bloop_bass = Inst(sr, "triangle", cutoff=900 * bright, attack=0.004, perc=0.22, release=0.05, glide=7.0, glide_time=0.03, sub=0.4)
    pad = Inst(sr, "triangle", cutoff=800, attack=0.5, decay=0.4, sustain=0.8, release=0.6, detune=8.0)

    song.pad("pad", pad, chords, range(32), 52, 0.05)
    bounce = [(0, 0, 3), (3, 0, 1), (4, 12, 2), (6, 0, 2), (8, 7, 3), (11, 0, 1), (12, 12, 2), (14, 10, 2)]
    creep = [(0, 0, 4), (6, 0, 2), (8, 0, 4), (14, 12, 2)]
    song.bass("bass", bloop_bass, chords, bars_of((0, 24)), bounce, 28, 0.38)
    song.bass("bass", bloop_bass, chords, bars_of((24, 32)), creep, 28, 0.4)

    song.melody("lead", mallet, 0, SLIME_A, 0.34)
    song.melody("lead", mallet, 8, SLIME_B, 0.26)
    song.melody("plink", plink, 8, SLIME_B, 0.06, transpose=12)
    song.melody("lead", mallet, 16, SLIME_A, 0.34)
    song.melody("plink", plink, 16, SLIME_A, 0.05, transpose=-12)
    song.melody("lead", mallet, 24, SLIME_C, 0.3)

    for bar in range(32):
        tones = voice(chord_at(chords, bar), 76)
        song.drums("drips", bar, "......o.......x.", lambda k: hit("drip", sr, 0, freq=round(midi_freq(tones[k % 3] + 12), 1)), 0.13)
        if bar >= 24 and bar % 2 == 1:
            for j in range(4):
                song.drums("drips", bar, "." * (12 + j) + "x", hit("bloop", sr, j, freq=260.0 + 70.0 * j, rise=1.2), 0.16)
        song.drums("drums", bar, "X.....x...X....." if bar < 24 else "X.........X.....", hit("kick", sr, 0, f0=48.0, decay=16.0, length=0.18), 0.6)
        song.drums("drums", bar, "....x.......x..o", hit("snare", sr, 0, tone=420.0, decay=40.0, length=0.08, bright=0.7, body=0.8), 0.22)
        song.drums("drums", bar, "..x...x...x...x.", lambda k: hit("hat", sr, k % 3), 0.07)
    if intense:
        for bar in range(32):
            song.drums("drums", bar, "o.o.o.o.o.o.o.o.", lambda k: hit("hat", sr, 3 + k % 3, length=0.02), 0.06)
            song.drums("drums", bar, "........X..x....", hit("kick", sr, 0, f0=48.0, decay=16.0, length=0.18), 0.45)
            song.drums("drums", bar, ".x.......x......", hit("tom", sr, 2, freq=210.0, length=0.2, decay=14.0), 0.14)
        song.arp("plink", plink, chords, range(0, 8), 64, [0, 1, 2, 3, 2, 1], 1, 0.035)

    return song.mix({"lead": 0.4, "plink": 0.3, "drips": 0.75, "pad": 0.5, "drums": 0.15},
                    {"size": 1.45, "feedback": 0.84, "damp": 0.22}, wet=0.5,
                    echoes={"drips": (3, 0.42, 0.45), "lead": (6, 0.2, 0.12)})


SHADOW = {"bpm": 76, "key": "B minor", "bars": 24}
SHADOW_CHORDS = parse_chords("Bmadd9 | Gmaj7 | Em | F#sus4 F# | Bm | Gmaj7 | Em | F# | "
                             "Dmaj7 | A | G | F# | Em | G | Asus4 A | F# | "
                             "Bmadd9 | Gmaj7 | Em | F#sus4 F# | Bm | Gmaj7 | Em | F#")
SHADOW_A = parse_melody("f#5:8 c#6:4 d6:4 | b5:12 a5:4 | g5:8 f#5:4 e5:4 | c#5:12 r:4 | "
                        "d5:4 f#5:4 b5:8 | a5:8 f#5:8 | g5:4 b5:4 e6:8 | c#6:8 a#5:8")
SHADOW_B = parse_melody("f#5:8 a5:4 c#6:4 | e6:12 c#6:4 | d6:8 b5:4 g5:4 | a#5:12 r:4 | "
                        "g5:8 b5:4 e6:4 | d6:8 b5:8 | c#6:8 e6:8 | f#6:8 c#6:4 a#5:4")
SHADOW_A_END = parse_melody("f#5:8 r:8")


def song_shadow_realm(intense=False):
    """Shadow realm: slow and cold, FM glass lead in a huge hall, breathy pad, whispers, heartbeat."""
    song = Song(SHADOW["bpm"], SHADOW["bars"])
    sr = song.sr
    bright = 1.25 if intense else 1.0
    chords = SHADOW_CHORDS
    glass = Inst(sr, "fm", fm_ratio=3.0, fm_index=1.4, fm_decay=0.35, cutoff=3200 * bright, attack=0.04,
                 decay=0.6, sustain=0.55, release=1.0, vibrato=0.003, vib_rate=4.2, vib_delay=0.4)
    pad = Inst(sr, "saw", cutoff=850 * bright, poles=2, attack=0.9, decay=0.6, sustain=0.85, release=1.4, detune=9.0, noise=0.08)
    drone = Inst(sr, "sine", cutoff=400, attack=0.4, sustain=0.95, release=0.8, sub=0.5)
    music_box = Inst(sr, "partials", partials=CELESTA_PARTIALS, attack=0.002, release=0.25)

    song.pad("pad", pad, chords, range(24), 54, 0.035)
    song.bass("drone", drone, chords, range(24), [(0, 0, 16)], 35, 0.26)
    song.melody("lead", glass, 0, SHADOW_A, 0.15)
    song.melody("lead", glass, 8, SHADOW_B, 0.14)
    song.melody("lead", glass, 16, SHADOW_A[:7] + SHADOW_A_END, 0.15)
    song.arp("box", music_box, chords, range(16, 24), 83, [0, 1, 2, 3], 4, 0.07)
    if intense:
        song.arp("box", music_box, chords, range(0, 16), 83, [0, 2, 1, 3], 2, 0.05)

    for bar in range(0, 24, 4):
        song.add("whisper", hit("whisper", sr, bar, length=2.2), bar, 0, 0.4)
    for bar in range(8, 16, 2):
        song.add("whisper", hit("whisper", sr, 50 + bar, length=1.4), bar, 8, 0.3)
    for bar in (7, 15):
        song.add("drums", hit("swell", sr, bar, length=round(16 * song.step / sr, 3), top=4000.0), bar, 0, 0.18)
    for bar in range(24):
        song.drums("drums", bar, "X..o............", hit("kick", sr, 0, f0=38.0, f1=60.0, decay=9.0, length=0.35), 0.62)
        if bar >= 16:
            song.drums("drums", bar, "o...o...o...o...", lambda k: hit("hat", sr, k % 2, length=0.012), 0.08)
    if intense:
        for bar in range(24):
            song.drums("drums", bar, "........X..o....", hit("kick", sr, 0, f0=38.0, f1=60.0, decay=9.0, length=0.35), 0.5)
            song.drums("drums", bar, "........x.......", hit("snare", sr, 1, tone=150.0, decay=10.0, length=0.35, bright=0.3), 0.18)
            song.drums("drums", bar, "..o...o...o...o.", lambda k: hit("hat", sr, 2 + k % 2, length=0.02), 0.07)

    return song.mix({"lead": 0.7, "pad": 0.6, "box": 0.8, "whisper": 0.9, "drums": 0.3, "drone": 0.15},
                    {"size": 1.9, "feedback": 0.885, "damp": 0.5}, wet=0.75, echoes={"lead": (3, 0.4, 0.3)})


FORGE = {"bpm": 120, "key": "G minor (phrygian dominant)", "bars": 32}
FORGE_CHORDS_A = "Gm | Gm | Ab | Gm | Eb | F | D | D"
FORGE_CHORDS = parse_chords(f"{FORGE_CHORDS_A} | {FORGE_CHORDS_A} | Cm | Gm | Ab | Eb | Cm | D | Gm | D | {FORGE_CHORDS_A}")
FORGE_A = parse_melody("g4:2 g4:1 bb4:1 d5:4 c5:2 bb4:2 c5:4 | d5:2 eb5:2 d5:2 c5:2 bb4:4 g4:4 | "
                       "ab4:2 c5:2 eb5:4 d5:2 c5:2 ab4:4 | g4:6 bb4:2 d5:8 | eb5:4 d5:2 c5:2 bb4:4 g4:4 | "
                       "f4:2 a4:2 c5:4 f5:4 eb5:4 | d5:4 f#5:4 a5:4 f#5:4 | eb5:4 d5:4 c5:4 a4:4")
FORGE_B = parse_melody("c5:4 eb5:4 g5:6 f5:2 | d5:4 bb4:4 g4:8 | ab4:4 c5:4 eb5:4 ab5:4 | g5:6 f5:2 eb5:4 bb4:4 | "
                       "c5:2 d5:2 eb5:2 f5:2 g5:4 eb5:4 | f#5:4 a5:4 d6:4 c6:4 | bb5:4 a5:2 g5:2 d5:4 bb4:4 | "
                       "a4:4 c5:4 eb5:4 f#5:4")


def song_ember_forge(intense=False):
    """Ember forge: driving taiko and anvil rhythm, galloping saw bass, brass lead, power chords."""
    song = Song(FORGE["bpm"], FORGE["bars"])
    sr = song.sr
    bright = 1.25 if intense else 1.0
    chords = FORGE_CHORDS
    brass = Inst(sr, "saw", cutoff=1300 * bright, poles=2, filter_env=1.6, filter_decay=0.15, attack=0.02,
                 decay=0.2, sustain=0.7, release=0.1, vibrato=0.004, vib_rate=5.5, vib_delay=0.2)
    bass = Inst(sr, "saw", cutoff=650 * bright, attack=0.003, decay=0.1, sustain=0.55, release=0.04, sub=0.6)
    power = Inst(sr, "saw", cutoff=1700 * bright, poles=2, attack=0.005, perc=0.18, release=0.08, detune=7.0)

    eighths = [(k, 12 if k in (4, 12) else 0, 1.6) for k in range(0, 16, 2)]
    gallop = [(k, 12 if k == 8 else 0, 0.9) for k in (0, 2, 3, 4, 6, 7, 8, 10, 11, 12, 14, 15)]
    song.bass("bass", bass, chords, bars_of((0, 8), (24, 32)), eighths, 31, 0.24)
    song.bass("bass", bass, chords, bars_of((8, 24)), gallop, 31, 0.24)

    song.melody("lead", brass, 0, FORGE_A, 0.15)
    song.melody("lead", brass, 8, FORGE_A, 0.13, transpose=12)
    song.melody("lead", brass, 8, FORGE_A, 0.07)
    song.melody("lead", brass, 16, FORGE_B, 0.15)
    if intense:
        song.melody("lead", brass, 24, FORGE_A, 0.1, transpose=12)

    for bar in bars_of((8, 24)):
        for k in (0, 3, 6):
            for note in voice((chord_at(chords, bar, k)[0], CHORD_INTERVALS["5"]), 55):
                song.note("power", power, bar, k, 2, note, 0.045)

    for bar in range(32):
        song.drums("drums", bar, "X.....x.X.......", hit("taiko", sr, 0, freq=62.0), 0.55)
        song.drums("drums", bar, ".............xo.", hit("tom", sr, 3, freq=140.0, length=0.3), 0.25)
        anvil = "....X.......X.x." if bar < 24 else "X...X...X.x.X.x."
        song.drums("anvil", bar, anvil, lambda k: hit("anvil", sr, 0, freq=1650.0 if k % 16 != 14 else 1900.0), 0.12)
        if 8 <= bar < 24:
            song.drums("drums", bar, "X.......X.......", hit("kick", sr, 0, decay=12.0), 0.6)
            song.drums("drums", bar, "....x.......x...", hit("snare", sr, 0, tone=200.0), 0.3)
        song.drums("drums", bar, "o.x.o.x.o.x.o.x.", lambda k: hit("shaker", sr, k % 4), 0.09)
    if intense:
        for bar in range(32):
            song.drums("drums", bar, "X.......X.......", hit("kick", sr, 0, decay=12.0), 0.45)
            song.drums("drums", bar, "..x...x...x...x.", hit("taiko", sr, 1, freq=88.0), 0.3)
            song.drums("drums", bar, "....x.......x..o", hit("snare", sr, 0, tone=200.0), 0.25)

    return song.mix({"lead": 0.3, "power": 0.25, "anvil": 0.5, "drums": 0.25, "bass": 0.05},
                    {"size": 0.95, "feedback": 0.76, "damp": 0.45}, wet=0.35, echoes={"anvil": (3, 0.3, 0.25)})


# =================================================================== boss themes (D-092)
# Phase one keeps the biome's colour at a fight tempo; phase two (p2=True) is 12 % faster with
# double-time drums, extra percussion, the lead doubled an octave up and brighter filters.

P2_TEMPO = 1.12

BONE_KING = {"bpm": 138, "key": "D minor", "bars": 24}
BONE_KING_CHORDS = parse_chords("Dm | Dm | C | Dm | Bb | C | A | A | "
                                "Gm | Dm | Bb | A | Gm | Dm | Bb A | Dm | "
                                "Dm | Dm | C | Dm | Bb | C | A | A")
# Dies irae (Gregorian, public domain) as the Bone King's motif.
BONE_KING_A = parse_melody("f5:4 e5:4 f5:4 d5:4 | e5:4 c5:4 d5:8 | f5:4 f5:4 g5:4 f5:4 | e5:4 d5:4 c5:4 d5:4 | "
                           "a5:4 a5:2 c6:2 bb5:4 a5:4 | g5:4 bb5:4 a5:4 g5:4 | f5:4 e5:4 c#5:4 e5:4 | a5:8 c#5:4 e5:4")
BONE_KING_B = parse_melody("d6:4 bb5:4 g5:4 bb5:4 | a5:4 f5:4 d5:8 | f5:4 bb5:4 d6:4 c6:4 | c#6:8 a5:8 | "
                           "g5:2 a5:2 bb5:4 d6:4 g6:4 | f6:4 e6:2 d6:2 a5:8 | bb5:4 a5:4 g5:4 f5:4 | e5:4 c#5:4 a4:4 c#5:4")


def song_bone_king(p2=False):
    """Bone King: Dies irae on a bright organ, harpsichord 16ths, bells on every phrase, timpani."""
    song = Song(round(BONE_KING["bpm"] * (P2_TEMPO if p2 else 1.0)), BONE_KING["bars"])
    sr = song.sr
    bright = 1.3 if p2 else 1.0
    chords = BONE_KING_CHORDS
    organ = Inst(sr, "organ", harmonics=((1, 1.0), (2, 0.7), (3, 0.45), (4, 0.3), (6, 0.15), (8, 0.08)),
                 cutoff=2600 * bright, attack=0.012, decay=0.2, sustain=0.75, release=0.12, trem=0.1, trem_rate=6.5)
    choir = Inst(sr, "saw", cutoff=900 * bright, poles=2, attack=0.25, decay=0.3, sustain=0.9, release=0.4, detune=10.0, noise=0.1)
    harpsichord = Inst(sr, "pulse", duty=0.22, cutoff=2600 * bright, attack=0.002, perc=0.1, release=0.04)
    bass = Inst(sr, "pulse", cutoff=800, attack=0.004, decay=0.1, sustain=0.6, release=0.03, sub=0.6)
    bell = Inst(sr, "partials", partials=BELL_PARTIALS, attack=0.002, release=0.5)

    song.pad("pad", choir, chords, range(24), 50, 0.04)
    pulse16 = [(k, 12 if k % 4 == 2 else 0, 0.85) for k in range(16)]
    song.bass("bass", bass, chords, range(24), pulse16, 26, 0.26)
    song.melody("lead", organ, 0, BONE_KING_A, 0.17)
    song.melody("lead", organ, 8, BONE_KING_B, 0.16)
    song.melody("lead", organ, 16, BONE_KING_A, 0.17)
    song.melody("lead", organ, 16, BONE_KING_A, 0.07, transpose=12)
    if p2:
        song.melody("lead", organ, 0, BONE_KING_A + BONE_KING_B, 0.06, transpose=12)
    song.arp("harps", harpsichord, chords, range(24), 62, [0, 1, 2, 3, 2, 1], 1, 0.04)
    for bar in range(0, 24, 2 if p2 else 4):
        song.note("bells", bell, bar, 0, 16, root_of(chord_at(chords, bar), 74), 0.14)

    for bar in range(24):
        song.drums("drums", bar, "X.......X.x.....", hit("kick", sr, 0), 0.75)
        song.drums("drums", bar, "....X.......X...", hit("snare", sr, 0), 0.4)
        song.drums("drums", bar, ".x.x.x.x.x.x.x.x", lambda k: hit("hat", sr, k % 3), 0.07)
        timpani = hit("tom", sr, 0, freq=round(midi_freq(root_of(chord_at(chords, bar), 38)), 1), length=0.6, decay=6.0, noise=0.3)
        song.drums("timp", bar, "X.....x.X.......", timpani, 0.35)
        if p2:
            song.drums("drums", bar, "..x...x.....x.x.", hit("kick", sr, 0), 0.55)
            song.drums("drums", bar, "o.o.o.o.o.o.o.o.", lambda k: hit("hat", sr, 3 + k % 3, length=0.02), 0.06)
            if bar % 4 == 3:
                song.drums("drums", bar, "............xxxx", lambda k: hit("snare", sr, k % 2), 0.3)
                for k, f in ((8, 200.0), (9, 170.0), (10, 140.0), (11, 110.0)):
                    song.drums("timp", bar, "." * k + "x", hit("tom", sr, 1, freq=f), 0.3)

    return song.mix({"lead": 0.3, "pad": 0.4, "harps": 0.25, "bells": 0.6, "timp": 0.3, "drums": 0.12},
                    {"size": 1.15, "feedback": 0.8, "damp": 0.4}, wet=0.45, echoes={"lead": (3, 0.22, 0.15)})


SLIME_QUEEN = {"bpm": 142, "key": "E minor", "bars": 24}
SLIME_QUEEN_CHORDS = parse_chords("Em | C | Am | B | Em | C | F | B | "
                                  "Am | Em | F | B | Am | Em | C | B | "
                                  "Em | C | Am | B | Em | C | F | B")
SLIME_QUEEN_A = parse_melody("e5:2 g5:2 b5:2 g5:2 e5:2 d#5:2 e5:4 | c5:2 e5:2 g5:2 e5:2 c6:4 b5:4 | "
                             "a5:2 c6:2 e6:2 c6:2 a5:2 g5:2 a5:4 | b5:4 a5:2 g5:2 f#5:4 d#5:4 | "
                             "e6:4 b5:4 g5:4 e5:4 | g5:2 a5:2 g5:2 e5:2 c5:4 e5:4 | f5:4 a5:4 c6:4 a5:4 | "
                             "b5:6 a5:2 f#5:4 d#5:4")
SLIME_QUEEN_B = parse_melody("a4:2 a4:2 c5:2 e5:2 a5:4 g5:4 | g5:2 f#5:2 e5:2 b4:2 e5:8 | "
                             "f5:2 f5:2 a5:2 c6:2 b5:4 a5:4 | f#5:2 g5:2 a5:2 b5:2 d#6:8 | "
                             "e6:4 c6:4 a5:4 e5:4 | g5:4 b5:4 e6:8 | e6:2 d6:2 c6:2 b5:2 g5:4 e5:4 | "
                             "d#5:4 f#5:4 a5:4 b5:4")


def song_slime_queen(p2=False):
    """Slime Queen: frantic marimba and square lead, gliding bloop bass, bubble bursts, drips."""
    song = Song(round(SLIME_QUEEN["bpm"] * (P2_TEMPO if p2 else 1.0)), SLIME_QUEEN["bars"])
    sr = song.sr
    bright = 1.3 if p2 else 1.0
    chords = SLIME_QUEEN_CHORDS
    mallet = Inst(sr, "partials", partials=MALLET_PARTIALS, attack=0.002, release=0.1)
    square = Inst(sr, "pulse", duty=0.25, cutoff=2400 * bright, attack=0.006, decay=0.15, sustain=0.55, release=0.06, vibrato=0.004)
    bloop_bass = Inst(sr, "triangle", cutoff=1000 * bright, attack=0.003, perc=0.15, release=0.04, glide=9.0, glide_time=0.025, sub=0.5)
    pad = Inst(sr, "pulse", duty=0.5, cutoff=700 * bright, attack=0.2, decay=0.4, sustain=0.75, release=0.3, detune=8.0)

    song.pad("pad", pad, chords, range(24), 52, 0.03)
    octaves = [(k, 12 if k % 4 == 2 else 0, 1.6) for k in range(0, 16, 2)]
    song.bass("bass", bloop_bass, chords, range(24), octaves, 28, 0.38)
    song.melody("lead", mallet, 0, SLIME_QUEEN_A, 0.3)
    song.melody("lead2", square, 0, SLIME_QUEEN_A, 0.07, transpose=-12)
    song.melody("lead", mallet, 8, SLIME_QUEEN_B, 0.3)
    song.melody("lead2", square, 8, SLIME_QUEEN_B, 0.1)
    song.melody("lead", mallet, 16, SLIME_QUEEN_A, 0.3)
    song.melody("lead2", square, 16, SLIME_QUEEN_A, 0.1)
    if p2:
        song.melody("lead2", square, 0, SLIME_QUEEN_A + SLIME_QUEEN_B, 0.05, transpose=12)

    for bar in range(24):
        tones = voice(chord_at(chords, bar), 76)
        song.drums("drips", bar, "...o.......o..x.", lambda k: hit("drip", sr, 0, freq=round(midi_freq(tones[k % 3] + 12), 1)), 0.12)
        if bar % 2 == 1 or p2:
            for j in range(4):
                song.drums("drips", bar, "." * (12 + j) + "x", hit("bloop", sr, j, freq=240.0 + 80.0 * j, rise=1.3), 0.14)
        song.drums("drums", bar, "X.....X...X.....", hit("kick", sr, 0, f0=48.0, decay=15.0), 0.75)
        song.drums("drums", bar, "....X.......X...", hit("snare", sr, 0, tone=300.0, decay=24.0, length=0.12), 0.35)
        song.drums("drums", bar, "..x...x...x...x.", lambda k: hit("hat", sr, k % 3), 0.08)
        if p2:
            song.drums("drums", bar, "o.o.o.o.o.o.o.o.", lambda k: hit("hat", sr, 3 + k % 3, length=0.02), 0.06)
            song.drums("drums", bar, "..X.....X.....X.", hit("kick", sr, 0, f0=48.0, decay=15.0), 0.5)
            song.drums("drums", bar, ".x.....x.x......", hit("tom", sr, 2, freq=220.0, length=0.2, decay=14.0), 0.15)

    return song.mix({"lead": 0.3, "lead2": 0.2, "drips": 0.7, "pad": 0.4, "drums": 0.1},
                    {"size": 1.3, "feedback": 0.8, "damp": 0.25}, wet=0.4, echoes={"drips": (3, 0.4, 0.4)})


SHADOW_LORD = {"bpm": 132, "key": "B minor", "bars": 24}
SHADOW_LORD_CHORDS = parse_chords("Bm | G | Em | F# | Bm | G | C | F# | "
                                  "Em | Bm | G | F# | Em | Bm | C | F# | "
                                  "Bm | G | Em | F# | Bm | G | C | F#")
SHADOW_LORD_A = parse_melody("b5:6 a5:2 f#5:4 d5:4 | g5:6 f#5:2 d5:4 b4:4 | e5:4 g5:4 b5:4 e6:4 | c#6:8 a#5:8 | "
                             "d6:6 c#6:2 b5:4 f#5:4 | g5:4 b5:4 d6:4 g6:4 | e6:4 c6:4 g5:4 e5:4 | f#5:8 a#5:4 c#6:4")
SHADOW_LORD_B = parse_melody("b5:4 e6:4 g6:4 f#6:4 | f#6:8 d6:4 b5:4 | d6:4 b5:4 g5:4 b5:4 | a#5:8 c#6:8 | "
                             "e6:4 d6:2 c#6:2 b5:4 g5:4 | f#5:4 b5:4 d6:8 | c6:4 e6:4 g6:4 e6:4 | c#6:4 a#5:4 f#5:4 c#5:4")


def song_shadow_lord(p2=False):
    """Shadow Lord: cold FM glass over a pulsing octave bass, whisper swells, half-time drums."""
    song = Song(round(SHADOW_LORD["bpm"] * (P2_TEMPO if p2 else 1.0)), SHADOW_LORD["bars"])
    sr = song.sr
    bright = 1.3 if p2 else 1.0
    chords = SHADOW_LORD_CHORDS
    glass = Inst(sr, "fm", fm_ratio=3.0, fm_index=1.8, fm_decay=0.25, cutoff=3400 * bright, attack=0.015,
                 decay=0.3, sustain=0.6, release=0.35, vibrato=0.004, vib_rate=5.0)
    pad = Inst(sr, "saw", cutoff=900 * bright, poles=2, attack=0.4, decay=0.4, sustain=0.85, release=0.6, detune=11.0, noise=0.1)
    bass = Inst(sr, "pulse", duty=0.4, cutoff=700 * bright, attack=0.004, decay=0.1, sustain=0.6, release=0.04, sub=0.6)
    arp = Inst(sr, "sine", cutoff=4000, attack=0.002, perc=0.12, release=0.05)

    song.pad("pad", pad, chords, range(24), 54, 0.035)
    octave8 = [(k, 12 if k % 4 == 2 else 0, 1.7) for k in range(0, 16, 2)]
    song.bass("bass", bass, chords, range(24), octave8, 35, 0.27)
    song.melody("lead", glass, 0, SHADOW_LORD_A, 0.17)
    song.melody("lead", glass, 8, SHADOW_LORD_B, 0.16)
    song.melody("lead", glass, 16, SHADOW_LORD_A, 0.17)
    song.melody("lead", glass, 16, SHADOW_LORD_A, 0.06, transpose=-12)
    if p2:
        song.melody("lead", glass, 0, SHADOW_LORD_A + SHADOW_LORD_B, 0.05, transpose=12)
    song.arp("arp", arp, chords, range(24), 71, [0, 1, 2, 3, 2, 1, 0, 2], 1, 0.05)

    for bar in range(0, 24, 2 if p2 else 4):
        song.add("whisper", hit("whisper", sr, 100 + bar, length=1.8), bar, 0, 0.45)
    for bar in range(24):
        song.drums("drums", bar, "X.........X.....", hit("kick", sr, 0, f0=40.0, decay=11.0, length=0.3), 0.8)
        song.drums("drums", bar, "........X.......", hit("snare", sr, 1, tone=170.0, decay=12.0, length=0.3, bright=0.35), 0.42)
        song.drums("drums", bar, "..x...x...x...x.", lambda k: hit("hat", sr, k % 3), 0.07)
        if p2:
            song.drums("drums", bar, "X...X...X...X...", hit("kick", sr, 0, f0=40.0, decay=11.0, length=0.3), 0.55)
            song.drums("drums", bar, "....x.......x..x", hit("snare", sr, 1, tone=170.0, decay=12.0, length=0.3, bright=0.35), 0.25)
            song.drums("drums", bar, "o.o.o.o.o.o.o.o.", lambda k: hit("hat", sr, 3 + k % 3, length=0.02), 0.06)
            if bar % 4 == 3:
                song.add("drums", hit("swell", sr, bar, length=round(16 * song.step / sr, 3)), bar, 0, 0.16)

    return song.mix({"lead": 0.6, "pad": 0.5, "arp": 0.5, "whisper": 0.9, "drums": 0.2},
                    {"size": 1.7, "feedback": 0.86, "damp": 0.45}, wet=0.6, echoes={"lead": (3, 0.35, 0.25)})


EMBER_GOLEM = {"bpm": 146, "key": "G minor (phrygian dominant)", "bars": 24}
EMBER_GOLEM_CHORDS = parse_chords("Gm | Ab | Gm | F | Gm | Ab | Bb | D | "
                                  "Eb | D | Cm | D | Eb | F | D | D | "
                                  "Gm | Ab | Gm | F | Gm | Ab | Bb | D")
EMBER_GOLEM_A = parse_melody("g4:2 g4:2 bb4:2 g4:2 d5:4 c5:4 | c5:2 c5:2 eb5:2 c5:2 ab5:4 g5:4 | "
                             "g5:2 f5:2 eb5:2 d5:2 bb4:4 g4:4 | a4:2 c5:2 f5:4 eb5:4 c5:4 | "
                             "d5:2 d5:2 g5:2 d5:2 bb5:4 a5:4 | ab5:4 g5:2 f5:2 eb5:4 c5:4 | "
                             "d5:4 f5:4 bb5:4 d6:4 | c6:4 a5:4 f#5:4 d5:4")
EMBER_GOLEM_B = parse_melody("g5:4 bb5:4 eb6:6 d6:2 | d6:4 a5:4 f#5:8 | eb6:4 d6:2 c6:2 g5:4 eb5:4 | "
                             "f#5:4 a5:4 c6:4 a5:4 | bb5:4 g5:4 eb5:4 g5:4 | a5:4 c6:4 f6:4 c6:4 | "
                             "d6:6 c6:2 a5:4 f#5:4 | eb6:4 d6:4 c6:4 a5:4")


def song_ember_golem(p2=False):
    """Ember Golem: heavy taiko and kick, anvil on the backbeat, 16th saw bass, brass lead, stabs."""
    song = Song(round(EMBER_GOLEM["bpm"] * (P2_TEMPO if p2 else 1.0)), EMBER_GOLEM["bars"])
    sr = song.sr
    bright = 1.3 if p2 else 1.0
    chords = EMBER_GOLEM_CHORDS
    brass = Inst(sr, "saw", cutoff=1500 * bright, poles=2, filter_env=1.8, filter_decay=0.12, attack=0.015,
                 decay=0.15, sustain=0.7, release=0.08, vibrato=0.005, vib_rate=6.0, vib_delay=0.15)
    bass = Inst(sr, "saw", cutoff=700 * bright, attack=0.002, decay=0.08, sustain=0.5, release=0.03, sub=0.7)
    power = Inst(sr, "saw", cutoff=1900 * bright, poles=2, attack=0.004, perc=0.15, release=0.06, detune=8.0)

    sixteenths = [(k, 12 if k in (6, 14) else 0, 0.85) for k in range(16)]
    song.bass("bass", bass, chords, range(24), sixteenths, 31, 0.23)
    song.melody("lead", brass, 0, EMBER_GOLEM_A, 0.15)
    song.melody("lead", brass, 8, EMBER_GOLEM_B, 0.15)
    song.melody("lead", brass, 16, EMBER_GOLEM_A, 0.15)
    song.melody("lead", brass, 16, EMBER_GOLEM_A, 0.07, transpose=12)
    if p2:
        song.melody("lead", brass, 0, EMBER_GOLEM_A + EMBER_GOLEM_B, 0.06, transpose=12)
    for bar in range(24):
        for k in (0, 3, 6, 10) if p2 else (0, 3, 6):
            for note in voice((chord_at(chords, bar, k)[0], CHORD_INTERVALS["5"]), 55):
                song.note("power", power, bar, k, 2, note, 0.045)

    for bar in range(24):
        song.drums("drums", bar, "X.....x.X.......", hit("taiko", sr, 0, freq=60.0), 0.55)
        song.drums("drums", bar, "X.......X..X....", hit("kick", sr, 0, decay=12.0), 0.65)
        song.drums("drums", bar, "....X.......X...", hit("snare", sr, 0, tone=210.0), 0.35)
        song.drums("anvil", bar, "....X.......X.x.", lambda k: hit("anvil", sr, 0, freq=1650.0 if k % 16 != 14 else 1900.0), 0.13)
        song.drums("drums", bar, "o.x.o.x.o.x.o.x.", lambda k: hit("shaker", sr, k % 4), 0.09)
        if p2:
            song.drums("drums", bar, "..x...x...x...x.", hit("taiko", sr, 1, freq=90.0), 0.32)
            song.drums("drums", bar, "..X...X...X...X.", hit("kick", sr, 0, decay=12.0), 0.45)
            song.drums("anvil", bar, "X.......X.......", hit("anvil", sr, 1, freq=1200.0, decay=0.6), 0.1)
            if bar % 4 == 3:
                song.drums("drums", bar, "............XxXx", lambda k: hit("tom", sr, k % 2, freq=150.0 - 10.0 * (k % 16 - 12)), 0.3)

    return song.mix({"lead": 0.3, "power": 0.2, "anvil": 0.5, "drums": 0.2},
                    {"size": 0.95, "feedback": 0.76, "damp": 0.45}, wet=0.3, echoes={"anvil": (3, 0.3, 0.22)})


# =================================================================== ambient beds
# Quiet loops under the music. Noise beds are filtered circularly and every LFO/sine completes a
# whole number of cycles per loop, so the beds have no seam. Event times use a fixed seed.

def _noise(n, seed):
    rng = random.Random(seed)
    return [rng.random() * 2.0 - 1.0 for _ in range(n)]


def _lfo(n, cycles, phase=0.0, depth=1.0, offset=0.0):
    w = TAU * cycles / n
    return [offset + depth * math.sin(w * i + phase) for i in range(n)]


def _loop_sine(n, sr, freq, amp):
    cycles = max(1, round(freq * n / sr))  # whole cycles per loop
    w = TAU * cycles / n
    return [amp * math.sin(w * i) for i in range(n)]


def _scatter(buf, rng, count, make, gain_range):
    n = len(buf)
    for _ in range(count):
        mix_into(buf, int(rng.random() * n), make(rng), gain_range[0] + rng.random() * (gain_range[1] - gain_range[0]))


def _scale(buf, gain):
    return [v * gain for v in buf]


def ambient_crypt():
    """Crypt: hollow wind through the corridors, distant drips in a stone hall, far chains, rumble."""
    sr = AMBIENT_SR
    n = int(48 * sr)
    rng = random.Random(101)
    gust = [a * b for a, b in zip(_lfo(n, 3, 0.0, 0.3, 0.6), _lfo(n, 7, 1.0, 0.25, 0.75))]
    wind = [v * g for v, g in zip(biquad(_noise(n, 1), "lp", 380.0, 0.7, sr, True), gust)]
    howl = [v * g for v, g in zip(biquad(_noise(n, 2), "bp", 520.0, 7.0, sr, True), _lfo(n, 5, 0.5, 0.5, 0.5))]
    rumble = biquad(biquad(_noise(n, 3), "lp", 70.0, 0.7, sr, True), "lp", 70.0, 0.7, sr, True)
    events = [0.0] * n
    _scatter(events, rng, 22, lambda r: hit("drip", sr, r.randrange(4), freq=round(800.0 + r.random() * 900.0)), (0.08, 0.2))

    def chain(r):
        cluster = [0.0] * int(0.7 * sr)
        for j in range(3 + r.randrange(4)):
            mix_into(cluster, int(j * (0.05 + r.random() * 0.1) * sr), hit("clink", sr, r.randrange(6), freq=round(2200.0 + r.random() * 1200.0)), 0.6 + r.random() * 0.4)
        return cluster

    _scatter(events, rng, 4, chain, (0.05, 0.09))
    wet = reverb(events, sr, size=1.4, feedback=0.86, damp=0.5)
    return [_scale(wind, 0.5), _scale(howl, 0.6), _scale(rumble, 2.5), _scale(events, 0.35), _scale(wet, 1.6)]


def ambient_slime_grotto():
    """Slime grotto: bubbling pools, many tuned drips with long cave echo, damp low noise."""
    sr = AMBIENT_SR
    n = int(44 * sr)
    rng = random.Random(202)
    damp = [v * g for v, g in zip(biquad(_noise(n, 11), "lp", 250.0, 0.7, sr, True), _lfo(n, 4, 0.0, 0.25, 0.75))]
    wet_noise = [v * g for v, g in zip(biquad(_noise(n, 12), "bp", 900.0, 2.0, sr, True), _lfo(n, 6, 2.0, 0.4, 0.5))]
    events = [0.0] * n

    def bubbles(r):
        burst = [0.0] * int(0.8 * sr)
        base = 160.0 + r.random() * 200.0
        for j in range(3 + r.randrange(6)):
            mix_into(burst, int(j * (0.03 + r.random() * 0.06) * sr),
                     hit("bloop", sr, r.randrange(5), freq=round(base * (0.8 + r.random() * 0.6)), length=0.12, rise=round(0.6 + r.random() * 0.8, 2)),
                     0.5 + r.random() * 0.5)
        return burst

    _scatter(events, rng, 20, bubbles, (0.12, 0.28))
    _scatter(events, rng, 34, lambda r: hit("drip", sr, r.randrange(5), freq=round(1000.0 + r.random() * 1200.0)), (0.08, 0.2))
    _scatter(events, rng, 4, lambda r: hit("bloop", sr, 9, freq=round(90.0 + r.random() * 40.0), length=0.3, rise=0.5), (0.35, 0.5))
    wet = reverb(echo(events, int(0.29 * sr), 0.35, 0.4), sr, size=1.6, feedback=0.88, damp=0.25)
    return [_scale(damp, 0.9), _scale(wet_noise, 0.25), _scale(events, 0.4), _scale(wet, 1.6)]


def ambient_shadow_realm():
    """Shadow realm: deep beating drone, airy shimmer, whispers far away in a cold hall."""
    sr = AMBIENT_SR
    n = int(52 * sr)
    rng = random.Random(303)
    swell = _lfo(n, 2, 0.0, 0.35, 0.65)
    drone = [(a + b + c) * s for a, b, c, s in zip(_loop_sine(n, sr, 55.0, 0.5), _loop_sine(n, sr, 55.25, 0.45),
                                                   _loop_sine(n, sr, 110.4, 0.18), swell)]
    shimmer = [v * g for v, g in zip(biquad(_noise(n, 21), "hp", 5000.0, 0.7, sr, True), _lfo(n, 3, 1.3, 0.5, 0.5))]
    hollow = [v * g for v, g in zip(biquad(_noise(n, 22), "bp", 300.0, 3.0, sr, True), _lfo(n, 5, 0.7, 0.5, 0.5))]
    events = [0.0] * n
    _scatter(events, rng, 8, lambda r: hit("whisper", sr, r.randrange(1000), length=round(0.9 + r.random() * 1.5, 2)), (0.25, 0.45))
    _scatter(events, rng, 2, lambda r: hit("swell", sr, r.randrange(1000), length=3.0, top=2500.0), (0.15, 0.2))
    wet = reverb(events, sr, size=1.9, feedback=0.89, damp=0.55)
    return [_scale(drone, 0.6), _scale(shimmer, 0.15), _scale(hollow, 0.35), _scale(events, 0.25), _scale(wet, 2.0)]


def ambient_ember_forge():
    """Ember forge: roaring furnace, crackling embers, hissing coals, far-away hammer blows."""
    sr = AMBIENT_SR
    n = int(46 * sr)
    rng = random.Random(404)
    breath = [a * b for a, b in zip(_lfo(n, 6, 0.0, 0.3, 0.7), _lfo(n, 11, 2.0, 0.2, 0.8))]
    roar = [v * g for v, g in zip(biquad(biquad(_noise(n, 31), "lp", 160.0, 0.8, sr, True), "lp", 220.0, 0.7, sr, True), breath)]
    hiss = [v * g for v, g in zip(biquad(_noise(n, 32), "bp", 3000.0, 1.5, sr, True), _lfo(n, 4, 0.3, 0.4, 0.6))]
    crackle = [0.0] * n
    density = _lfo(n, 9, 0.0, 0.5, 0.5)
    i = 0
    while i < n:
        i += int((0.02 + rng.random() * 0.12) * sr)
        if i < n and rng.random() < 0.35 + 0.65 * density[i]:
            pop = rng.random() < 0.08
            mix_into(crackle, i, hit("crackle", sr, rng.randrange(8), length=0.012 if pop else 0.004, tone=0.25 if pop else 0.6),
                     (0.6 if pop else 0.15) + rng.random() * 0.25)
    far = [0.0] * n
    for k in range(3):
        start = int((k + 0.3 + rng.random() * 0.4) * n / 3)
        mix_into(far, start, hit("boom", sr, k, freq=48.0, length=1.4), 0.5)
        mix_into(far, start, hit("anvil", sr, k, freq=1300.0, decay=0.5), 0.12)
    far = biquad(far, "lp", 900.0, 0.7, sr, True)
    wet = reverb(far, sr, size=1.5, feedback=0.84, damp=0.6)
    return [_scale(roar, 2.2), _scale(hiss, 0.1), _scale(crackle, 0.8), _scale(far, 0.5), _scale(wet, 1.4)]


def ambient_village():
    """Village: soft wind and rustling leaves, birds calling now and then."""
    sr = AMBIENT_SR
    n = int(56 * sr)
    rng = random.Random(505)
    wind = [v * g for v, g in zip(biquad(_noise(n, 41), "lp", 600.0, 0.7, sr, True), _lfo(n, 4, 0.0, 0.35, 0.65))]
    leaves = [v * g for v, g in zip(biquad(_noise(n, 42), "bp", 2500.0, 1.2, sr, True),
                                    [max(0.0, x) for x in _lfo(n, 9, 0.5, 1.0, -0.2)])]
    birds = [0.0] * n

    def warble(r):
        song = [0.0] * int(1.4 * sr)
        base = 2600.0 + r.random() * 1200.0
        for j in range(4 + r.randrange(5)):
            f0 = base * (0.85 + r.random() * 0.3)
            f1 = f0 * (0.8 + r.random() * 0.5)
            mix_into(song, int(j * 0.11 * sr), hit("chirp", sr, j, f0=round(f0), f1=round(f1), length=0.07), 0.6 + r.random() * 0.4)
        return song

    def call(r):
        song = [0.0] * int(0.9 * sr)
        mix_into(song, 0, hit("chirp", sr, 0, f0=2300.0, f1=2250.0, length=0.16), 0.8)
        mix_into(song, int(0.25 * sr), hit("chirp", sr, 1, f0=1850.0, f1=1800.0, length=0.32), 0.8)
        return song

    _scatter(birds, rng, 9, warble, (0.12, 0.25))
    _scatter(birds, rng, 5, call, (0.1, 0.18))
    wet = reverb(birds, sr, size=0.8, feedback=0.7, damp=0.4)
    return [_scale(wind, 0.5), _scale(leaves, 0.1), _scale(birds, 1.5), _scale(wet, 1.2)]


# =================================================================== stingers (D-097 transitions)
# One-shot pieces, not loops. A transition stinger is written in the tempo and key of its biome
# loop: its musical part ends on a bar line, then STINGER_TAIL seconds of reverb tail follow.
# MusicPlayer starts the loop (bar one) exactly where the tail begins (MusicRules.STINGER_TAIL),
# so the stinger leads into the loop like an intro. Victory stingers close a boss fight with a
# bVI - bVII - I cadence in the boss's key (minor turns major) and ring out over the ambient bed.

STINGER_TAIL = 1.5  # seconds, must match MusicRules.STINGER_TAIL
VICTORY_TAIL = 2.5
STINGER_PAD = 4.0  # silent seconds rendered after the tail so the circular reverb cannot wrap
LOUDNESS_STINGER = -15.5
LOUDNESS_VICTORY = -16.5  # calmer than the loops: the fight is over


def stinger_song(bpm, musical_steps, tail, swing=0.0):
    """A Song long enough for the musical part, its tail and a silent pad."""
    step = int(round(60.0 / bpm / 4.0 * MUSIC_SR))
    total = musical_steps * step + int((tail + STINGER_PAD) * MUSIC_SR)
    return Song(bpm, math.ceil(total / (16 * step)), swing=swing)


def finish_stinger(name, sr, layers, target_db, keep_samples, tail):
    """Sums the layers, matches the loudness of the kept part, trims to musical part + tail and
    fades the last part of the tail to silence (no click at the end)."""
    mixed = [0.0] * len(layers[0])
    for layer in layers:
        mixed = [a + b for a, b in zip(mixed, layer)]
    mixed = one_pole_hp(mixed, 18.0, sr)[:keep_samples]
    for _ in range(4):
        gain = 10.0 ** ((target_db - loudness_db(mixed, sr)) / 20.0)
        mixed = soft_limit([v * gain for v in mixed])
        if abs(gain - 1.0) < 0.01:
            break
    fade_n = int(min(tail, 1.0) * sr)
    for i in range(fade_n):
        x = i / fade_n
        mixed[keep_samples - fade_n + i] *= math.cos(x * math.pi * 0.5) ** 2
    for i in range(min(64, keep_samples)):
        mixed[i] *= i / 64.0
    out_dir = OUT
    out_dir.mkdir(parents=True, exist_ok=True)
    data = array("h", (int(max(-1.0, min(1.0, v)) * 32767) for v in mixed))
    with wave.open(str(out_dir / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data.tobytes())
    peak = 20.0 * math.log10(max(1e-9, max(abs(v) for v in mixed)))
    musical = (keep_samples - int(tail * sr)) / sr
    return (f"{name}: {keep_samples / sr:.2f} s (loop enters at {musical:.2f} s), peak {peak:.1f} dBFS, "
            f"loudness {loudness_db(mixed, sr):.1f} dB")


def _stinger_result(song, layers, musical_steps, tail):
    keep = musical_steps * song.step + int(tail * song.sr)
    return {"layers": layers, "keep": keep, "tail": tail}


def transition_crypt():
    """Crypt entry: a far bell on the dominant, organ Gm -> A swelling, celesta falling to the
    leading tone and a timpani roll on A that lands on bar one (Dm) of the crypt loop."""
    steps = 32
    song = stinger_song(CRYPT["bpm"], steps, STINGER_TAIL)
    sr = song.sr
    organ_pad = Inst(sr, "organ", harmonics=((1, 1.0), (2, 0.6), (4, 0.25)), sub=0.3, cutoff=1100,
                     attack=1.2, decay=0.5, sustain=0.9, release=1.0, trem=0.07, trem_rate=5.2)
    pedal = Inst(sr, "organ", harmonics=((1, 1.0), (2, 0.4), (3, 0.1)), cutoff=500, attack=0.6, sustain=0.9, release=0.8)
    celesta = Inst(sr, "partials", partials=CELESTA_PARTIALS, attack=0.002, release=0.3)
    bell = Inst(sr, "partials", partials=BELL_PARTIALS, attack=0.002, release=0.8)
    chords = parse_chords("Gm | A")
    song.pad("pad", organ_pad, chords, range(2), 50, 0.07)
    song.bass("pedal", pedal, chords, range(2), [(0, 0, 16)], 33, 0.28)
    song.note("bells", bell, 0, 0, 24, 69, 0.24)
    song.note("bells", bell, 1, 8, 8, 81, 0.06)
    song.melody("celesta", celesta, 0, parse_melody("r:8 d6:2 c6:2 bb5:4 | a5:4 g5:2 f5:2 e5:4 c#5:4"), 0.2)
    timp = hit("tom", sr, 0, freq=round(midi_freq(45), 1), length=0.7, decay=5.0, noise=0.25)
    song.drums("timp", 0, "X...............", timp, 0.3)
    song.drums("timp", 1, "........-o-oxxXX", hit("tom", sr, 2, freq=round(midi_freq(45), 1), length=0.35, decay=9.0, noise=0.3), 0.3)
    layers = song.mix({"pad": 0.45, "celesta": 0.55, "bells": 0.6, "timp": 0.35, "pedal": 0.1},
                      {"size": 1.25, "feedback": 0.83, "damp": 0.42}, wet=0.55)
    return _stinger_result(song, layers, steps, STINGER_TAIL)


def transition_slime_grotto():
    """Slime grotto entry: bubbles rising out of a pool, an E minor marimba figure, then a B
    dominant run with gliding bass and a little drum fill into bar one (Em) of the grotto loop."""
    steps = 32
    song = stinger_song(SLIME["bpm"], steps, STINGER_TAIL, swing=0.33)
    sr = song.sr
    mallet = Inst(sr, "partials", partials=MALLET_PARTIALS, attack=0.002, release=0.12)
    bloop_bass = Inst(sr, "triangle", cutoff=900, attack=0.004, perc=0.22, release=0.05, glide=7.0, glide_time=0.03, sub=0.4)
    pad = Inst(sr, "triangle", cutoff=800, attack=0.6, decay=0.4, sustain=0.8, release=0.8, detune=8.0)
    chords = parse_chords("Em | B")
    song.pad("pad", pad, chords, range(2), 52, 0.05)
    for k in range(8):
        song.add("drips", hit("bloop", sr, k, freq=round(170.0 + 45.0 * k), length=0.12, rise=1.1), 0, k * 2, 0.08 + 0.015 * k)
    song.drums("drips", 0, "......o.......x.", lambda k: hit("drip", sr, 0, freq=round(midi_freq((88, 91, 95)[k % 3]), 1)), 0.13)
    song.drums("drips", 1, "......o...o...x.", lambda k: hit("drip", sr, 1, freq=round(midi_freq((83, 87, 90)[k % 3] + 12), 1)), 0.13)
    song.melody("lead", mallet, 0, parse_melody("r:8 e4:2 g4:2 b4:2 e5:2 | f#5:2 d#5:2 b4:2 d#5:2 f#5:2 a5:2 b5:4"), 0.3)
    song.bass("bass", bloop_bass, chords, [1], [(0, 0, 3), (4, 12, 2), (8, 7, 3), (12, 0, 2), (14, 12, 2)], 28, 0.36)
    song.drums("drums", 1, "X.......X.......", hit("kick", sr, 0, f0=48.0, decay=16.0, length=0.18), 0.5)
    song.drums("drums", 1, "............x.xX", hit("snare", sr, 0, tone=420.0, decay=40.0, length=0.08, bright=0.7, body=0.8), 0.22)
    layers = song.mix({"lead": 0.4, "drips": 0.75, "pad": 0.5, "drums": 0.15},
                      {"size": 1.45, "feedback": 0.84, "damp": 0.22}, wet=0.5, echoes={"drips": (3, 0.42, 0.45)})
    return _stinger_result(song, layers, steps, STINGER_TAIL)


def transition_shadow_realm():
    """Shadow realm entry: a whisper in the dark, a cold glass call on the dominant, a deep drone
    on F# and a reverse swell that pulls into bar one (Bmadd9) of the shadow loop. 1.5 bars."""
    steps = 24
    song = stinger_song(SHADOW["bpm"], steps, STINGER_TAIL)
    sr = song.sr
    glass = Inst(sr, "fm", fm_ratio=3.0, fm_index=1.4, fm_decay=0.35, cutoff=3200, attack=0.04,
                 decay=0.6, sustain=0.55, release=1.0, vibrato=0.003, vib_rate=4.2, vib_delay=0.4)
    pad = Inst(sr, "saw", cutoff=850, poles=2, attack=1.4, decay=0.6, sustain=0.85, release=1.4, detune=9.0, noise=0.08)
    drone = Inst(sr, "sine", cutoff=400, attack=1.0, sustain=0.95, release=1.0, sub=0.5)
    song.note("pad", pad, 0, 0, 12, 66, 0.035)
    song.note("pad", pad, 0, 0, 12, 71, 0.035)
    song.note("pad", pad, 0, 0, 12, 73, 0.035)
    song.note("pad", pad, 0, 12, 12, 66, 0.035)
    song.note("pad", pad, 0, 12, 12, 70, 0.035)
    song.note("pad", pad, 0, 12, 12, 73, 0.035)
    song.note("drone", drone, 0, 0, 24, 42, 0.26)
    song.note("lead", glass, 0, 4, 8, 85, 0.13)
    song.note("lead", glass, 0, 12, 12, 82, 0.13)
    song.add("whisper", hit("whisper", sr, 7, length=2.0), 0, 0, 0.4)
    song.add("drums", hit("swell", sr, 3, length=round(12 * song.step / sr, 3), top=4000.0), 0, 12, 0.2)
    song.drums("drums", 0, "........X..o....", hit("kick", sr, 0, f0=38.0, f1=60.0, decay=9.0, length=0.35), 0.45)
    layers = song.mix({"lead": 0.7, "pad": 0.6, "whisper": 0.9, "drums": 0.3, "drone": 0.15},
                      {"size": 1.9, "feedback": 0.885, "damp": 0.5}, wet=0.75, echoes={"lead": (3, 0.4, 0.3)})
    return _stinger_result(song, layers, steps, STINGER_TAIL)


def transition_ember_forge():
    """Ember forge entry: three anvil blows over a furnace boom, a phrygian brass call, D power
    stabs and a taiko roll that lands on bar one (Gm) of the forge loop."""
    steps = 32
    song = stinger_song(FORGE["bpm"], steps, STINGER_TAIL)
    sr = song.sr
    brass = Inst(sr, "saw", cutoff=1300, poles=2, filter_env=1.6, filter_decay=0.15, attack=0.02,
                 decay=0.2, sustain=0.7, release=0.15, vibrato=0.004, vib_rate=5.5, vib_delay=0.2)
    bass = Inst(sr, "saw", cutoff=650, attack=0.003, decay=0.1, sustain=0.55, release=0.04, sub=0.6)
    power = Inst(sr, "saw", cutoff=1700, poles=2, attack=0.005, perc=0.18, release=0.08, detune=7.0)
    song.add("drums", hit("boom", sr, 0, freq=48.0, length=1.4), 0, 0, 0.5)
    song.drums("anvil", 0, "X.....x.....X...", lambda k: hit("anvil", sr, 0, freq=1650.0 if k != 12 else 1900.0), 0.14)
    song.melody("lead", brass, 0, parse_melody("r:8 d4:3 d4:1 eb4:2 d4:2 | f#4:2 a4:2 d5:4 eb5:2 d5:2 c5:2 a4:2"), 0.15)
    chords = parse_chords("D | D")
    song.bass("bass", bass, chords, [1], [(k, 12 if k in (4, 12) else 0, 1.6) for k in range(0, 16, 2)], 31, 0.22)
    for k in (0, 3, 6):
        for note in voice((parse_chord("D")[0], CHORD_INTERVALS["5"]), 55):
            song.note("power", power, 1, k, 2, note, 0.045)
    song.drums("drums", 1, "X.......-o-oxxXX", hit("taiko", sr, 0, freq=62.0), 0.45)
    song.drums("drums", 1, "o.x.o.x.o.x.o.x.", lambda k: hit("shaker", sr, k % 4), 0.08)
    layers = song.mix({"lead": 0.3, "power": 0.25, "anvil": 0.5, "drums": 0.25, "bass": 0.05},
                      {"size": 0.95, "feedback": 0.76, "damp": 0.45}, wet=0.35, echoes={"anvil": (3, 0.3, 0.25)})
    return _stinger_result(song, layers, steps, STINGER_TAIL)


# Victory cadence bVI - bVII - I: tonic note (MIDI) of every boss key.
VICTORY_BPM = 96
VICTORY_STEPS = 24


def _victory_layers(song, tonic, chord_inst, lead_inst, bass_inst, chord_vol, lead_vol, low):
    """Chords on steps 0, 8, 16 (the tonic held into the tail), the chord thirds as a rising top
    line and roots in the bass."""
    roots = [tonic - 4, tonic - 2, tonic]
    lengths = [8, 8, 20]
    for index, (root, length) in enumerate(zip(roots, lengths)):
        start = index * 8
        voiced = [low + (root - low) % 12 + i for i in (0, 4, 7)]
        for note in voiced:
            song.note("chords", chord_inst, 0, start, length, note, chord_vol, 1.0)
        song.note("lead", lead_inst, 0, start, length, root + 16, lead_vol)
        song.note("bass", bass_inst, 0, start, length, root - 24 if root - 24 >= 28 else root - 12, 0.26)
    return roots


def victory_bone_king():
    """Bone King beaten: organ Bb - C - D major, bells ring the D, a timpani stroke on each chord."""
    song = stinger_song(VICTORY_BPM, VICTORY_STEPS, VICTORY_TAIL)
    sr = song.sr
    organ = Inst(sr, "organ", harmonics=((1, 1.0), (2, 0.6), (4, 0.25)), sub=0.2, cutoff=1500,
                 attack=0.05, decay=0.4, sustain=0.85, release=1.2, trem=0.07, trem_rate=5.2)
    lead = Inst(sr, "organ", harmonics=((1, 1.0), (2, 0.55), (3, 0.3), (4, 0.2)), cutoff=2400,
                attack=0.03, decay=0.3, sustain=0.8, release=1.0, trem=0.1, trem_rate=5.6)
    pedal = Inst(sr, "organ", harmonics=((1, 1.0), (2, 0.4)), cutoff=500, attack=0.05, sustain=0.9, release=1.0)
    bell = Inst(sr, "partials", partials=BELL_PARTIALS, attack=0.002, release=1.0)
    _victory_layers(song, 62, organ, lead, pedal, 0.06, 0.14, 50)
    song.note("bells", bell, 0, 16, 24, 74, 0.22)
    song.note("bells", bell, 0, 18, 24, 81, 0.08)
    for k, note in ((0, 34), (8, 36), (16, 38)):
        song.add("timp", hit("tom", sr, 0, freq=round(midi_freq(note + 12), 1), length=0.8, decay=4.5, noise=0.25), 0, k, 0.35)
    layers = song.mix({"chords": 0.45, "lead": 0.35, "bells": 0.6, "timp": 0.35},
                      {"size": 1.25, "feedback": 0.83, "damp": 0.42}, wet=0.55)
    return _stinger_result(song, layers, VICTORY_STEPS, VICTORY_TAIL)


def victory_slime_queen():
    """Slime Queen beaten: marimba C - D - E major arpeggios, a bubble burst, drips in E major."""
    song = stinger_song(VICTORY_BPM, VICTORY_STEPS, VICTORY_TAIL)
    sr = song.sr
    pad = Inst(sr, "triangle", cutoff=900, attack=0.15, decay=0.4, sustain=0.8, release=1.2, detune=8.0)
    mallet = Inst(sr, "partials", partials=MALLET_PARTIALS, attack=0.002, release=0.3)
    bass = Inst(sr, "triangle", cutoff=900, attack=0.004, perc=0.5, release=0.3, glide=7.0, glide_time=0.03, sub=0.4)
    roots = _victory_layers(song, 64, pad, mallet, bass, 0.05, 0.3, 52)
    for index, root in enumerate(roots):
        for j, offset in enumerate((0, 4, 7, 12)):
            song.note("arp", mallet, 0, index * 8 + j, 1, root + 12 + offset, 0.16)
    for j in range(5):
        song.add("drips", hit("bloop", sr, j, freq=round(260.0 + 70.0 * j), length=0.12, rise=1.2), 0, 16 + j * 0.5, 0.14)
    for k, note in ((18, 88), (20, 92), (22, 95)):
        song.add("drips", hit("drip", sr, 0, freq=round(midi_freq(note), 1)), 0, k, 0.12)
    layers = song.mix({"lead": 0.4, "arp": 0.4, "drips": 0.75, "chords": 0.5},
                      {"size": 1.45, "feedback": 0.84, "damp": 0.22}, wet=0.5, echoes={"drips": (3, 0.42, 0.45)})
    return _stinger_result(song, layers, VICTORY_STEPS, VICTORY_TAIL)


def victory_shadow_lord():
    """Shadow Lord beaten: glass G - A - B major in a huge hall, music box on the B, a last whisper."""
    song = stinger_song(VICTORY_BPM, VICTORY_STEPS, VICTORY_TAIL)
    sr = song.sr
    pad = Inst(sr, "saw", cutoff=900, poles=2, attack=0.3, decay=0.6, sustain=0.85, release=1.6, detune=9.0, noise=0.05)
    glass = Inst(sr, "fm", fm_ratio=3.0, fm_index=1.4, fm_decay=0.35, cutoff=3200, attack=0.03,
                 decay=0.6, sustain=0.55, release=1.4, vibrato=0.003, vib_rate=4.2, vib_delay=0.4)
    drone = Inst(sr, "sine", cutoff=400, attack=0.1, sustain=0.95, release=1.4, sub=0.5)
    box = Inst(sr, "partials", partials=CELESTA_PARTIALS, attack=0.002, release=0.4)
    _victory_layers(song, 59, pad, glass, drone, 0.035, 0.15, 54)
    for j, note in enumerate((83, 87, 90, 95)):
        song.note("box", box, 0, 16 + j, 2, note, 0.09)
    song.add("whisper", hit("whisper", sr, 31, length=1.6), 0, 18, 0.25)
    layers = song.mix({"lead": 0.7, "chords": 0.6, "box": 0.8, "whisper": 0.9, "bass": 0.15},
                      {"size": 1.9, "feedback": 0.885, "damp": 0.5}, wet=0.75, echoes={"lead": (3, 0.4, 0.3)})
    return _stinger_result(song, layers, VICTORY_STEPS, VICTORY_TAIL)


def victory_ember_golem():
    """Ember Golem beaten: brass Eb - F - G major with power stabs, taiko on each chord, the anvil
    rings out on the G."""
    song = stinger_song(VICTORY_BPM, VICTORY_STEPS, VICTORY_TAIL)
    sr = song.sr
    brass_pad = Inst(sr, "saw", cutoff=1200, poles=2, attack=0.04, decay=0.3, sustain=0.75, release=1.0, detune=7.0)
    brass = Inst(sr, "saw", cutoff=1400, poles=2, filter_env=1.6, filter_decay=0.15, attack=0.02,
                 decay=0.2, sustain=0.7, release=0.8, vibrato=0.004, vib_rate=5.5, vib_delay=0.2)
    bass = Inst(sr, "saw", cutoff=650, attack=0.003, decay=0.2, sustain=0.6, release=0.6, sub=0.6)
    _victory_layers(song, 67, brass_pad, brass, bass, 0.035, 0.13, 55)
    for k, freq in ((0, 62.0), (8, 70.0), (16, 62.0)):
        song.add("drums", hit("taiko", sr, 0, freq=freq), 0, k, 0.5)
    song.add("anvil", hit("anvil", sr, 2, freq=1960.0, decay=0.9), 0, 16, 0.14)
    layers = song.mix({"lead": 0.3, "chords": 0.25, "anvil": 0.5, "drums": 0.25},
                      {"size": 0.95, "feedback": 0.76, "damp": 0.45}, wet=0.4, echoes={"anvil": (3, 0.3, 0.25)})
    return _stinger_result(song, layers, VICTORY_STEPS, VICTORY_TAIL)


# =================================================================== jobs

# name -> (renderer, kwargs, output dir, sample rate, loudness target, info)
JOBS = {
    "village": (legacy_village, {}, None, SR, None, "92 BPM, C major, 16 bars (legacy)"),
    "dungeon": (legacy_dungeon, {}, None, SR, None, "128 BPM, A minor, 16 bars (legacy)"),
    "boss": (legacy_boss, {}, None, SR, None, "150 BPM, D minor, 16 bars (legacy)"),
}
for _biome, _fn, _meta in (("crypt", song_crypt, CRYPT), ("slime_grotto", song_slime_grotto, SLIME),
                           ("shadow_realm", song_shadow_realm, SHADOW), ("ember_forge", song_ember_forge, FORGE)):
    _info = f"{_meta['bpm']} BPM, {_meta['key']}, {_meta['bars']} bars"
    JOBS[f"dungeon_{_biome}"] = (_fn, {}, OUT, MUSIC_SR, LOUDNESS_DUNGEON, _info)
    JOBS[f"dungeon_{_biome}_intense"] = (_fn, {"intense": True}, OUT, MUSIC_SR, LOUDNESS_INTENSE, _info + ", champion drums")
for _boss, _fn, _meta in (("bone_king", song_bone_king, BONE_KING), ("slime_queen", song_slime_queen, SLIME_QUEEN),
                          ("shadow_lord", song_shadow_lord, SHADOW_LORD), ("ember_golem", song_ember_golem, EMBER_GOLEM)):
    JOBS[f"boss_{_boss}"] = (_fn, {}, OUT, MUSIC_SR, LOUDNESS_BOSS, f"{_meta['bpm']} BPM, {_meta['key']}, {_meta['bars']} bars")
    JOBS[f"boss_{_boss}_p2"] = (_fn, {"p2": True}, OUT, MUSIC_SR, LOUDNESS_BOSS_P2,
                                f"{round(_meta['bpm'] * P2_TEMPO)} BPM, {_meta['key']}, {_meta['bars']} bars, phase two")
for _name, _fn, _info in (("crypt", ambient_crypt, "48 s wind, drips, chains"),
                          ("slime_grotto", ambient_slime_grotto, "44 s bubbles, drips, cave"),
                          ("shadow_realm", ambient_shadow_realm, "52 s drone, whispers"),
                          ("ember_forge", ambient_ember_forge, "46 s furnace, crackle, hammer"),
                          ("village", ambient_village, "56 s wind, birds")):
    JOBS[f"ambient_{_name}"] = (_fn, {}, AMBIENT_OUT, AMBIENT_SR, LOUDNESS_AMBIENT, _info)
for _biome, _fn, _meta, _bars in (("crypt", transition_crypt, CRYPT, 2), ("slime_grotto", transition_slime_grotto, SLIME, 2),
                                  ("shadow_realm", transition_shadow_realm, SHADOW, 1.5),
                                  ("ember_forge", transition_ember_forge, FORGE, 2)):
    JOBS[f"transition_{_biome}"] = (_fn, {}, OUT, MUSIC_SR, LOUDNESS_STINGER,
                                    f"stinger, {_meta['bpm']} BPM, {_meta['key']}, {_bars} bars + {STINGER_TAIL} s tail")
for _boss, _fn, _key in (("bone_king", victory_bone_king, "Bb-C-D"), ("slime_queen", victory_slime_queen, "C-D-E"),
                         ("shadow_lord", victory_shadow_lord, "G-A-B"), ("ember_golem", victory_ember_golem, "Eb-F-G")):
    JOBS[f"victory_{_boss}"] = (_fn, {}, OUT, MUSIC_SR, LOUDNESS_VICTORY,
                                f"stinger, {VICTORY_BPM} BPM, {_key} major, {VICTORY_STEPS // 4} beats + {VICTORY_TAIL} s tail")
STINGER_PREFIXES = ("transition_", "victory_")


def run_job(name):
    renderer, kwargs, out_dir, sr, target, _info = JOBS[name]
    if out_dir is None:
        return renderer(**kwargs)
    if name.startswith(STINGER_PREFIXES):
        result = renderer(**kwargs)
        return finish_stinger(name, sr, result["layers"], target, result["keep"], result["tail"])
    return finish(name, out_dir, sr, renderer(**kwargs), target)


def measure():
    for folder in (OUT, AMBIENT_OUT):
        for path in sorted(folder.glob("*.wav")):
            with wave.open(str(path)) as w:
                sr = w.getframerate()
                data = array("h", w.readframes(w.getnframes()))
            samples = [v / 32768.0 for v in data]
            seconds, peak, rms, loud, seam = stats(samples, sr)
            if path.stem.startswith(STINGER_PREFIXES):
                # One-shot: no seam; the end must be silent (no click when it stops).
                tail = samples[-max(1, sr // 100):]
                end = 20.0 * math.log10(max(1e-9, math.sqrt(sum(v * v for v in tail) / len(tail))))
                print(f"{path.stem}: {seconds:.2f} s @ {sr} Hz, peak {peak:.1f} dBFS, RMS {rms:.1f} dBFS, "
                      f"loudness {loud:.1f} dB, one-shot, last 10 ms {end:.0f} dBFS")
                continue
            print(f"{path.stem}: {seconds:.1f} s @ {sr} Hz, peak {peak:.1f} dBFS, RMS {rms:.1f} dBFS, "
                  f"loudness {loud:.1f} dB, seam {seam:.2f}")


def main(args):
    if "--list" in args:
        for name, job in JOBS.items():
            print(f"{name}: {job[5]}")
        return
    if "--measure" in args:
        measure()
        return
    names = [n for n in JOBS if not args or any(word in n for word in args)]
    if not names:
        print("No track matches", " ".join(args))
        return
    # Longest jobs first so the pool stays busy.
    names.sort(key=lambda n: (JOBS[n][2] is None, "ambient" in n))
    with Pool(min(len(names), os.cpu_count() or 1)) as pool:
        for line in pool.imap_unordered(run_job, names):
            print(line, flush=True)


if __name__ == "__main__":
    main(sys.argv[1:])
