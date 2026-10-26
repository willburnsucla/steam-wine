#!/usr/bin/env python3
"""Write an MP3 of digital silence: MPEG-1 Layer III frames with all-zero side info and main
data, which every decoder turns into zero samples. Used by mp3test.c; no audio is downloaded.

Usage: make-silent-mp3.py <out.mp3> <seconds>
"""
import sys

HEADER = bytes([0xFF, 0xFB, 0x90, 0x64])  # MPEG-1 Layer III, 128 kbps, 44.1 kHz, joint stereo
FRAME_BYTES = 417                         # 144 * 128000 / 44100, no padding
SAMPLES_PER_FRAME = 1152


def main():
    out, seconds = sys.argv[1], float(sys.argv[2])
    frames = int(seconds * 44100 / SAMPLES_PER_FRAME)
    frame = HEADER + bytes(FRAME_BYTES - len(HEADER))
    with open(out, "wb") as f:
        f.write(frame * frames)
    print(f"{out}: {frames} frames, {frames * SAMPLES_PER_FRAME / 44100:.2f} s")


if __name__ == "__main__":
    main()
