import argparse
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
    "/data/data/com.termux/files/usr/share/fonts/TTF/DejaVuSansMono.ttf",
    "/System/Library/Fonts/Menlo.ttc",
    "C:\\Windows\\Fonts\\consola.ttf",
]


def find_font(path):
    if path:
        return path
    for candidate in FONT_CANDIDATES:
        if os.path.exists(candidate):
            return candidate
    sys.exit("no monospace font found, pass one with --font")


def glyph_bank(font_path, chars, cell_w, cell_h):
    scale = 8
    probe = ImageFont.truetype(font_path, 100)
    advance = probe.getlength("M") / 100.0
    size = int(round(scale * cell_w / advance))
    font = ImageFont.truetype(font_path, size)
    ascent, descent = font.getmetrics()
    y0 = max(0, (scale * cell_h - (ascent + descent)) // 2)
    bank = []
    for ch in chars:
        img = Image.new("L", (scale * cell_w, scale * cell_h), 0)
        ImageDraw.Draw(img).text((0, y0), ch, font=font, fill=255)
        arr = np.asarray(img, np.float32) / 255.0
        small = arr.reshape(cell_h, scale, cell_w, scale).mean(axis=(1, 3))
        bank.append(small.reshape(-1))
    bank = np.array(bank, np.float32)
    peak = bank.max()
    if peak > 0:
        bank /= peak
    return bank


def build_filter(args, width, height):
    if args.letterbox:
        scale = (
            f"scale={width}:{height}:flags=area:force_original_aspect_ratio=decrease,"
            f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=black"
        )
    else:
        scale = f"scale={width}:{height}:flags=area"
    return f"fps={args.fps},{scale},format=gray"


def main():
    ap = argparse.ArgumentParser(description="Convert a video into ASCII frames for the TWRP player")
    ap.add_argument("video")
    ap.add_argument("-o", "--output", default=os.path.join("frames", "frames.txt"))
    ap.add_argument("--cols", type=int, default=52)
    ap.add_argument("--rows", type=int, default=19)
    ap.add_argument("--fps", type=float, default=15)
    ap.add_argument("--cell-w", type=int, default=6)
    ap.add_argument("--cell-h", type=int, default=12)
    ap.add_argument("--black", type=float, default=10)
    ap.add_argument("--white", type=float, default=245)
    ap.add_argument("--font")
    ap.add_argument("--chars")
    ap.add_argument("--letterbox", action="store_true")
    args = ap.parse_args()

    chars = list(args.chars) if args.chars else [chr(c) for c in range(32, 127) if chr(c) != "\\"]
    if " " not in chars:
        chars.insert(0, " ")
    bank = glyph_bank(find_font(args.font), chars, args.cell_w, args.cell_h)
    bank_norm = (bank * bank).sum(1)

    width = args.cols * args.cell_w
    height = args.rows * args.cell_h
    cmd = [
        "ffmpeg", "-v", "error", "-i", args.video,
        "-vf", build_filter(args, width, height),
        "-fps_mode", "passthrough", "-f", "rawvideo", "-",
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    frame_bytes = width * height
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    count = 0
    span = max(args.white - args.black, 1.0)
    with open(args.output, "w", newline="\n") as out:
        while True:
            raw = proc.stdout.read(frame_bytes)
            if len(raw) < frame_bytes:
                break
            gray = np.frombuffer(raw, np.uint8).reshape(height, width).astype(np.float32)
            level = np.clip((gray - args.black) / span, 0, 1)
            blocks = (
                level.reshape(args.rows, args.cell_h, args.cols, args.cell_w)
                .transpose(0, 2, 1, 3)
                .reshape(args.rows * args.cols, args.cell_h * args.cell_w)
            )
            score = bank_norm[None, :] - 2 * blocks @ bank.T
            pick = score.argmin(1).reshape(args.rows, args.cols)
            for r in range(args.rows):
                out.write("".join(chars[i] for i in pick[r]) + "\n")
            count += 1
    proc.wait()
    if proc.returncode not in (0, None) or count == 0:
        sys.exit("ffmpeg failed or produced no frames")
    print(f"{count} frames written to {args.output}")


if __name__ == "__main__":
    main()
