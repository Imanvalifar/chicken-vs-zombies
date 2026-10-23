"""Procedurally synthesise the game's sound effects into assets/audio/*.wav"""
import math
import os
import random
import struct
import wave

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")
os.makedirs(OUT, exist_ok=True)
random.seed(7)


def write_wav(name, samples):
    peak = max(1e-6, max(abs(s) for s in samples))
    norm = 0.86 / peak
    data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * norm)) * 32767)) for s in samples)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print("wrote", path, f"{len(samples)/SR:.2f}s")


def env_exp(i, n, attack=0.004, curve=5.0):
    t = i / SR
    a = min(1.0, t / attack) if attack > 0 else 1.0
    return a * math.exp(-curve * t)


def noise():
    return random.uniform(-1, 1)


def lowpass(x, prev, k):
    return prev + (x - prev) * k


# ---------------------------------------------------------------- laser shot
n = int(SR * 0.12)
s = []
phase = 0.0
for i in range(n):
    t = i / SR
    f = 1500 * math.exp(-14 * t) + 220
    phase += 2 * math.pi * f / SR
    saw = (2 / math.pi) * math.asin(math.sin(phase))
    sq = 1.0 if math.sin(phase) > 0 else -1.0
    v = 0.55 * saw + 0.25 * sq + 0.10 * noise()
    s.append(v * env_exp(i, n, 0.002, 16))
write_wav("shoot.wav", s)

# ---------------------------------------------------------------- explosion
n = int(SR * 0.62)
s = []
lp = 0.0
for i in range(n):
    t = i / SR
    k = 0.06 + 0.5 * math.exp(-9 * t)
    lp = lowpass(noise(), lp, k)
    rumble = math.sin(2 * math.pi * (70 - 30 * min(1, t)) * t) * math.exp(-4 * t)
    v = lp * 1.5 + rumble * 0.5
    s.append(v * env_exp(i, n, 0.003, 4.2))
write_wav("explosion.wav", s)

# ---------------------------------------------------------------- small hit
n = int(SR * 0.07)
s = []
for i in range(n):
    t = i / SR
    v = math.sin(2 * math.pi * 1750 * t) * 0.5 + noise() * 0.5
    s.append(v * env_exp(i, n, 0.001, 45))
write_wav("hit.wav", s)

# ---------------------------------------------------------------- egg splat
n = int(SR * 0.2)
s = []
lp = 0.0
for i in range(n):
    t = i / SR
    lp = lowpass(noise(), lp, 0.22)
    v = lp * 1.2 + math.sin(2 * math.pi * 150 * t) * 0.45 * math.exp(-18 * t)
    s.append(v * env_exp(i, n, 0.002, 14))
write_wav("splat.wav", s)

# ---------------------------------------------------------------- power up
n = int(SR * 0.5)
s = []
notes = [523.25, 659.25, 783.99, 1046.5]
seg = n // len(notes)
for i in range(n):
    t = i / SR
    idx = min(len(notes) - 1, i // seg)
    f = notes[idx]
    local = (i % seg) / SR
    v = math.sin(2 * math.pi * f * t) * 0.6 + math.sin(2 * math.pi * f * 2 * t) * 0.18
    e = min(1.0, local / 0.01) * math.exp(-3.2 * local)
    s.append(v * e)
write_wav("powerup.wav", s)

# ---------------------------------------------------------------- chicken cluck
n = int(SR * 0.26)
s = [0.0] * n
for start, f0 in ((0.0, 520.0), (0.13, 420.0)):
    off = int(start * SR)
    ln = int(0.11 * SR)
    ph = 0.0
    for i in range(ln):
        t = i / SR
        f = f0 * (1 - 0.35 * t / 0.11)
        ph += 2 * math.pi * f / SR
        am = 0.55 + 0.45 * math.sin(2 * math.pi * 34 * t)
        v = (0.6 if math.sin(ph) > 0 else -0.6) * am
        v += noise() * 0.12
        if off + i < n:
            s[off + i] += v * env_exp(i, ln, 0.004, 16)
write_wav("cluck.wav", s)

# ---------------------------------------------------------------- wave start
n = int(SR * 0.75)
s = []
for i in range(n):
    t = i / SR
    v = (math.sin(2 * math.pi * 880 * t) * 0.5 + math.sin(2 * math.pi * 1320 * t) * 0.3
         + math.sin(2 * math.pi * 1760 * t) * 0.15)
    s.append(v * env_exp(i, n, 0.01, 4.0))
write_wav("wave.wav", s)

# ---------------------------------------------------------------- game over
n = int(SR * 1.4)
s = []
notes = [392.0, 329.63, 261.63, 196.0]
seg = n // len(notes)
ph = 0.0
for i in range(n):
    t = i / SR
    idx = min(len(notes) - 1, i // seg)
    local = (i % seg) / SR
    f = notes[idx] * (1 - 0.02 * local)
    ph += 2 * math.pi * f / SR
    v = (2 / math.pi) * math.asin(math.sin(ph)) * 0.6
    v += math.sin(2 * math.pi * f / 2 * t) * 0.25
    e = min(1.0, local / 0.01) * math.exp(-2.0 * local)
    s.append(v * e)
write_wav("gameover.wav", s)
