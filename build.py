import argparse
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
MARKER = "cq61tech"
SCRIPT_PATH = "META-INF/com/google/android/update-binary"
UPDATER_PATH = "META-INF/com/google/android/updater-script"
STAMP = (2024, 1, 1, 0, 0, 0)


def add(archive, name, data, mode):
    info = zipfile.ZipInfo(name, date_time=STAMP)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = (0o100000 | mode) << 16
    archive.writestr(info, data)


def read(path, mode="rb"):
    with open(os.path.join(ROOT, path), mode) as handle:
        return handle.read()


def set_shell(script, shell):
    lines = script.split(b"\n", 1)
    lines[0] = b"#!" + shell.encode()
    return b"\n".join(lines)


def set_content(script, rows):
    patched, count = re.subn(rb"(?m)^CONTENT=\d+$", b"CONTENT=%d" % rows, script)
    if count != 1:
        sys.exit("CONTENT assignment not found in script")
    return patched


def check_frames(data, rows):
    lines = data.split(b"\n")
    if lines and lines[-1] == b"":
        lines.pop()
    if not lines:
        sys.exit("frame file is empty")
    if len(lines) % rows:
        sys.exit(f"frame file has {len(lines)} lines, not a multiple of {rows}")
    widths = {len(line) for line in lines}
    if 0 in widths:
        sys.exit("frame file contains empty lines")
    if b"\r" in data:
        sys.exit("frame file contains carriage returns")
    if max(widths) > 54:
        print(f"warning: widest row is {max(widths)} columns", file=sys.stderr)
    return len(lines) // rows


def build_player(args):
    frames = read(args.frames)
    total = check_frames(frames, args.content_rows)
    script = read("src/update-binary.sh")
    script = set_shell(script, args.shell)
    script = set_content(script, args.content_rows)
    if not script.endswith(b"\n"):
        script += b"\n"
    payload = script + frames
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with zipfile.ZipFile(args.output, "w") as archive:
        add(archive, SCRIPT_PATH, payload, 0o755)
        add(archive, UPDATER_PATH, read("src/updater-script"), 0o644)
        add(archive, MARKER, b"", 0o644)
    print(f"{args.output}: {total} frames, {os.path.getsize(args.output)} bytes")


def build_calibration(args):
    script = set_shell(read("src/rows-calibration.sh"), args.shell)
    os.makedirs(os.path.dirname(os.path.abspath(args.calibration_output)), exist_ok=True)
    with zipfile.ZipFile(args.calibration_output, "w") as archive:
        add(archive, SCRIPT_PATH, script, 0o755)
        add(archive, UPDATER_PATH, read("src/updater-script"), 0o644)
    print(f"{args.calibration_output}: {os.path.getsize(args.calibration_output)} bytes")


def main():
    ap = argparse.ArgumentParser(description="Build the flashable zip")
    ap.add_argument("--frames", default=os.path.join(ROOT, "frames", "frames.txt"))
    ap.add_argument("--output", default=os.path.join(ROOT, "dist", "BadApple_TWRP.zip"))
    ap.add_argument("--shell", default="/sbin/sh")
    ap.add_argument("--content-rows", type=int, default=19)
    ap.add_argument("--calibration", action="store_true")
    ap.add_argument("--calibration-output", default=os.path.join(ROOT, "dist", "rows_calibration.zip"))
    args = ap.parse_args()
    if args.calibration:
        build_calibration(args)
    else:
        build_player(args)


if __name__ == "__main__":
    main()
