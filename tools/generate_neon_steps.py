import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
DURATION = 26.0
OUT = Path(__file__).resolve().parents[1] / "songs" / "neon-steps" / "Inst.wav"

random.seed(0x4A415645)
chords = [
    (130.81, 164.81, 196.00),  # C3 E3 G3
    (110.00, 130.81, 164.81),  # A2 C3 E3
    (87.31, 110.00, 130.81),   # F2 A2 C3
    (98.00, 123.47, 146.83),   # G2 B2 D3
]
melody = [261.63, 329.63, 392.00, 523.25, 493.88, 392.00, 329.63, 293.66]


def env(phase, attack=0.035, release=0.16):
    return min(1.0, phase / attack) * min(1.0, max(0.0, (1.0 - phase) / release))


def synth(t):
    beat = t * 2.0
    beat_index = int(beat)
    beat_phase = beat - beat_index
    bar = beat_index // 4
    chord = chords[bar % len(chords)]

    # Warm chord pad, deliberately simple and newly composed.
    pad = 0.0
    for i, frequency in enumerate(chord):
        drift = 1.0 + 0.0025 * math.sin(t * (0.35 + i * 0.11))
        pad += math.sin(2.0 * math.pi * frequency * drift * t + i * 0.8)
    pad *= 0.085 * (0.78 + 0.22 * math.sin(math.pi * beat_phase))

    bass_frequency = chord[0] / 2.0
    bass = 0.18 * math.sin(2.0 * math.pi * bass_frequency * t)
    bass += 0.045 * math.sin(2.0 * math.pi * bass_frequency * 2.0 * t)
    bass *= env(beat_phase, 0.025, 0.42)

    eighth = t * 4.0
    eighth_index = int(eighth)
    eighth_phase = eighth - eighth_index
    note = melody[(eighth_index + (bar % 2) * 2) % len(melody)]
    lead = math.sin(2.0 * math.pi * note * t)
    lead += 0.35 * math.sin(2.0 * math.pi * note * 2.0 * t)
    lead *= 0.105 * env(eighth_phase, 0.04, 0.28)

    kick_phase = beat_phase
    kick = math.sin(2.0 * math.pi * (52.0 + 70.0 * math.exp(-kick_phase * 18.0)) * kick_phase)
    kick *= 0.33 * math.exp(-kick_phase * 11.0)

    snare = 0.0
    if beat_index % 4 in (1, 3):
        noise = random.uniform(-1.0, 1.0)
        snare = noise * 0.16 * math.exp(-beat_phase * 18.0)
        snare += math.sin(2.0 * math.pi * 180.0 * beat_phase) * 0.08 * math.exp(-beat_phase * 13.0)

    hat_phase = eighth_phase
    hat = random.uniform(-1.0, 1.0) * 0.035 * math.exp(-hat_phase * 34.0)

    fade = min(1.0, t / 0.8) * min(1.0, max(0.0, (DURATION - t) / 1.0))
    mono = (pad + bass + lead + kick + snare + hat) * fade
    pan = 0.09 * math.sin(t * 0.7)
    return mono * (1.0 - pan), mono * (1.0 + pan)


OUT.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(OUT), "wb") as wav:
    wav.setnchannels(2)
    wav.setsampwidth(2)
    wav.setframerate(RATE)
    block = bytearray()
    for sample in range(int(RATE * DURATION)):
        left, right = synth(sample / RATE)
        left = math.tanh(left * 1.25) * 0.82
        right = math.tanh(right * 1.25) * 0.82
        block += struct.pack("<hh", int(left * 32767), int(right * 32767))
        if len(block) >= 262144:
            wav.writeframesraw(block)
            block.clear()
    wav.writeframes(block)

print(OUT)
