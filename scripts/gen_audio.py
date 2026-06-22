#!/usr/bin/env python3
"""silence.wav / alarm.wav 생성기 (§오디오 알람).
- silence: 극저진폭(거의 무음, 단 0 아님 → iOS가 '오디오 없음'으로 백그라운드 종료하는 것 방지) 1초 루프.
- alarm: 풀볼륨 알람음(880/988Hz 교대 비프) + 앞 0.3초 무음 패딩(첫 글리치 방지). 루프용.
이후 afconvert로 .caf 변환.
"""
import math
import struct
import wave

RATE = 44100


def write_wav(path, samples):
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = bytearray()
        for s in samples:
            v = max(-32767, min(32767, int(s)))
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))


def silence(seconds=1.0):
    n = int(RATE * seconds)
    # 50Hz, 진폭 4 (16-bit 만점 32767 대비 ~ -78dB) → 사실상 안 들리지만 0 아님.
    return [4 * math.sin(2 * math.pi * 50 * i / RATE) for i in range(n)]


def alarm(total=4.0, pad=0.3):
    out = [0.0] * int(RATE * pad)
    amp = 0.62 * 32767
    beep, gap = 0.22, 0.16
    t = pad
    freqs = [880.0, 988.0]
    fi = 0
    while t < total:
        f = freqs[fi % 2]
        fi += 1
        for i in range(int(RATE * beep)):
            # 짧은 페이드로 클릭 방지
            env = min(1.0, i / (RATE * 0.01), (int(RATE * beep) - i) / (RATE * 0.01))
            out.append(amp * env * math.sin(2 * math.pi * f * i / RATE))
        out += [0.0] * int(RATE * gap)
        t += beep + gap
    return out


if __name__ == "__main__":
    import sys
    outdir = sys.argv[1]
    write_wav(f"{outdir}/silence.wav", silence())
    write_wav(f"{outdir}/alarm.wav", alarm())
    print("wrote silence.wav, alarm.wav to", outdir)
