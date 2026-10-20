#!/usr/bin/env python3
"""Synthesize MacShell's UI sounds (macOS-style; Apple's own recordings are theirs and not redistributable).

Writes 48 kHz mono WAVs to ~/.local/share/sounds/macshell/:
  pop      volume change             soft water drop
  tink     small UI ticks            muted wooden tap
  glass    notification              deep, slow glass bell
  lock     lock screen appears       low thump with a muffled click
  unlock   unlocked                  two soft notes rising
  shutter  screenshot                soft camera shutter
  charge   charger connected         warm power chime
  trash    empty trash               muffled paper crumple
  alarm    the Clock's alarm         marimba phrase (loops while it rings)
  timer    a timer finishing         three-note marimba

House style: nothing sharp. Every sound has a soft (raised-cosine) attack instead of a click, is low-passed so there is
no glassy top end, decays slowly, and ends in a short room tail — deep and fluid rather than tick-y.
"""
import os
import wave
import numpy as np

SR = 48000
OUT = os.path.expanduser("~/.local/share/sounds/macshell")
rng = np.random.default_rng(7)


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def env(t, attack, decay, curve=1.6):
    """raised-cosine attack (no click), exponential decay with a soft knee"""
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    a = 0.5 - 0.5 * np.cos(np.pi * a)          # S-curve in, so the start is breathed rather than struck
    return a * np.exp(-(t / decay) ** curve)


def lowpass(x, cutoff, slope=1.0):
    """gentle spectral tilt: everything above `cutoff` rolls off smoothly (no resonance, no ringing)"""
    f = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    with np.errstate(divide="ignore"):
        g = 1.0 / (1.0 + (freqs / max(cutoff, 1.0)) ** (2.0 * slope))
    return np.fft.irfft(f * g, len(x))


def bandpass_noise(n, lo, hi):
    x = rng.standard_normal(n)
    f = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    f[(freqs < lo) | (freqs > hi)] = 0
    return np.fft.irfft(f, n)


def glide(f0, f1, t, k=14.0):
    """sine whose pitch slides from f0 to f1 — what makes a drop sound like liquid"""
    f = f1 + (f0 - f1) * np.exp(-t * k)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def bell(t, f0, ratios, amps, decays, attack=0.006):
    s = np.zeros_like(t)
    for r, a, d in zip(ratios, amps, decays):
        s += a * np.sin(2 * np.pi * f0 * r * t) * env(t, attack, d)
    return s


def verb(x, sec=0.22, mix=0.22, cutoff=2600):
    """a small, dark room: smears the tail so the sound settles instead of stopping"""
    n = int(SR * sec)
    ir = rng.standard_normal(n) * np.exp(-np.linspace(0, 6, n))
    ir = lowpass(ir, cutoff)
    ir /= np.max(np.abs(ir)) or 1.0
    m = len(x) + n
    wet = np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)
    wet = wet[: len(x) + n] / (np.max(np.abs(wet)) or 1.0)
    dry = np.concatenate([x, np.zeros(n)])
    return (1 - mix) * dry + mix * wet


def finish(x, peak_db=-9.0, tail=0.05):
    x = np.asarray(x, dtype=np.float64)
    n = int(SR * tail)
    if n and len(x) > n:
        x[-n:] *= np.linspace(1, 0, n) ** 2      # a soft landing, never a cut
    x -= np.mean(x)
    peak = np.max(np.abs(x)) or 1.0
    return x / peak * (10 ** (peak_db / 20))


def write(name, x):
    os.makedirs(OUT, exist_ok=True)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


# ── Pop: a drop falling into water. Pitch slides down two octaves, the body is all low mid, the "plip" on top is
#    barely there and dull.
t = t_axis(0.26)                                                         # short enough that held volume keys don't smear
pop = glide(520, 165, t, 26) * env(t, 0.007, 0.062, 1.3)
pop += 0.45 * glide(260, 110, t, 18) * env(t, 0.010, 0.11, 1.2)          # the low body underneath
pop += 0.05 * lowpass(bandpass_noise(len(t), 300, 1600), 1100) * env(t, 0.004, 0.02)
pop = lowpass(pop, 1500, 1.2)
write("pop", finish(verb(pop, 0.14, 0.16), -9))

# ── Tink: a fingertip on soft wood. Low, short, no metal in it.
t = t_axis(0.28)
tink = bell(t, 620, [1.0, 2.04, 3.1], [1.0, 0.30, 0.10], [0.055, 0.03, 0.018], 0.004)
tink += 0.3 * glide(760, 560, t, 40) * env(t, 0.004, 0.04)
tink = lowpass(tink, 2200, 1.3)
write("tink", finish(verb(tink, 0.16, 0.2), -13))

# ── Glass (notifications): the same chime an octave down, slow in, long and round on the way out.
t = t_axis(2.0)
glass = bell(t, 784, [1.0, 2.01, 3.01, 4.21], [1.0, 0.34, 0.14, 0.05], [0.75, 0.42, 0.22, 0.12], 0.016)
glass += 0.42 * bell(t, 784 * 1.5, [1.0, 2.0], [0.5, 0.14], [0.5, 0.22], 0.022)       # the fifth above it
glass += 0.22 * bell(t, 392, [1.0, 2.0], [1.0, 0.2], [0.9, 0.4], 0.03)                # an octave below: the depth
glass = lowpass(glass, 3400, 1.1)
write("glass", finish(verb(glass, 0.35, 0.28), -10))

# ── Lock: a deep, soft thud. The click is inside the thud, not on top of it.
t = t_axis(0.5)
lock = 1.0 * glide(190, 72, t, 30) * env(t, 0.006, 0.13, 1.2)
lock += 0.5 * np.sin(2 * np.pi * 96 * t) * env(t, 0.01, 0.2, 1.1)
lock += 0.08 * lowpass(bandpass_noise(len(t), 200, 1400), 900) * env(t, 0.003, 0.025)
lock = lowpass(lock, 900, 1.4)
write("lock", finish(verb(lock, 0.22, 0.2, 1400), -10))

# ── Unlock: two warm notes rising (A4 → E5), each one breathed in.
t = t_axis(1.1)
n1 = bell(t, 440, [1.0, 2.0, 3.0], [1.0, 0.22, 0.06], [0.34, 0.18, 0.1], 0.012)
n2 = bell(t, 659.3, [1.0, 2.0, 3.0], [0.9, 0.2, 0.05], [0.46, 0.22, 0.1], 0.014)
off = int(SR * 0.11)
unlock = n1 + np.concatenate([np.zeros(off), n2])[: len(n1)]
unlock = lowpass(unlock, 2800, 1.2)
write("unlock", finish(verb(unlock, 0.3, 0.26), -12))

# ── Shutter: still two halves, but muffled — a shutter heard through a pocket.
def shutter_click(sec, lo, hi, body):
    t = t_axis(sec)
    x = lowpass(bandpass_noise(len(t), lo, hi), 1800) * env(t, 0.002, 0.03)
    x += 0.7 * np.sin(2 * np.pi * body * t) * env(t, 0.004, 0.045)
    return x
a = shutter_click(0.2, 200, 2200, 190)
b = shutter_click(0.26, 150, 1800, 140)
shut = np.zeros(int(SR * 0.5))
shut[: len(a)] += a
o = int(SR * 0.12)
shut[o: o + len(b)] += 0.85 * b
shut = lowpass(shut, 1600, 1.3)
write("shutter", finish(verb(shut, 0.2, 0.2, 1600), -10))

# ── Charge: a warm, round power chime (C4 with its octave), slow in.
t = t_axis(1.8)
charge = bell(t, 261.6, [1.0, 2.0, 3.01, 4.0], [1.0, 0.45, 0.14, 0.05], [0.8, 0.5, 0.25, 0.12], 0.02)
charge += 0.3 * bell(t, 523.3, [1.0, 2.0], [0.6, 0.12], [0.45, 0.2], 0.03)
charge = lowpass(charge, 2600, 1.2)
write("charge", finish(verb(charge, 0.32, 0.26), -11))

# ── Trash: a crumple with the paper taken out of it — soft, low, no crackle.
dur = 0.9
n = int(SR * dur)
trash = np.zeros(n)
for _ in range(55):
    pos = int(rng.uniform(0, 0.6) * SR)
    ln = int(rng.uniform(0.01, 0.045) * SR)
    seg = lowpass(bandpass_noise(ln, 120, 1200), 800) * np.hanning(ln) * rng.uniform(0.3, 1.0)
    trash[pos: pos + ln] += seg[: max(0, min(ln, n - pos))]
trash *= np.concatenate([np.linspace(0.5, 1, n // 3), np.linspace(1, 0.1, n - n // 3)])
trash = lowpass(trash, 1000, 1.3)
write("trash", finish(verb(trash, 0.25, 0.22, 1200), -13))

# ── Alarm / Timer: marimba, an octave below the old one, mallets wrapped in wool. One 2 s phrase, looped while ringing.
def marimba(f, sec=0.9):
    t = t_axis(sec)
    x = bell(t, f, [1.0, 3.94, 9.2], [1.0, 0.18, 0.03], [0.34, 0.09, 0.03], 0.006)
    return lowpass(x, 2600, 1.2)

phrase = [(0.00, 659.3), (0.12, 784.0), (0.24, 987.8), (0.36, 784.0),
          (0.72, 659.3), (0.84, 784.0), (0.96, 987.8), (1.08, 1318.5)]
alarm = np.zeros(int(SR * 2.0))
for at, f in phrase:
    m = marimba(f)
    o = int(at * SR)
    alarm[o: o + len(m)] += m[: max(0, min(len(m), len(alarm) - o))]
write("alarm", finish(verb(alarm, 0.3, 0.24), -9))

tdone = np.zeros(int(SR * 1.6))
for at, f in [(0.0, 784.0), (0.16, 987.8), (0.32, 1174.7)]:
    m = marimba(f, 1.1)
    o = int(at * SR)
    tdone[o: o + len(m)] += m[: max(0, min(len(m), len(tdone) - o))]
write("timer", finish(verb(tdone, 0.3, 0.24), -9))

print("wrote", ", ".join(sorted(os.listdir(OUT))), "to", OUT)
