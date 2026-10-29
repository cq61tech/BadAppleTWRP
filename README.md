# BadApple-TWRP

Plays Bad Apple!! as ASCII art inside the TWRP flash log. Flash the zip and the recovery console turns into a 15 fps player.

Credits: cq61tech

## How it works

- `update-binary` is a plain shell script. The ASCII frames are appended to the same file after a `__DATA__` marker.
- Every frame is padded to the height of the console and sent to the recovery as one block of `ui_print` commands, so each frame pushes the previous one off the screen.
- `set_progress` drives the install progress bar, so it works as a seek bar.
- The touchscreen is locked while the video plays, because touching the console disables its auto-scroll. It is restored when playback ends or the script is interrupted.

## Requirements

- A recovery that runs a shell `update-binary` and shows `ui_print` output (TWRP and forks).
- `/sbin/sh` in the recovery. If your recovery only has `/system/bin/sh`, build the zip with `--shell /system/bin/sh`.
- Tested on: Galaxy S9+ (SM-G965F) with TWRP. Other devices are unverified, reports are welcome.

## Quick start

1. Download `BadApple_TWRP.zip` from the Releases page.
2. Copy it to your SD card or internal storage.
3. Boot TWRP, Install, select the zip.

The first frames may look cropped or misaligned on other screens. Flash `rows_calibration.zip` once, count the fully visible numbered lines at the end, and use that number as `ba_rows` (see below).

## Tested Devices

| Device | Android Version | Codename | Recovery | Rec Version | Status |
| --- | --- | --- | --- |
| Galaxy S9+ | Android 16 | star2lte | TWRP | v3.7.0-9.0 | Working Good✅ |

## Settings

Settings are read from the root of any mounted storage. The zip name overrides files.

| Setting | File in storage root | Zip name | Default |
| --- | --- | --- | --- |
| Visible console rows | `ba_rows` (number) | `rows32` (two digits) | 28 |
| Delay between frames in seconds | `ba_delay` (for example `0.063`) | - | 0.063 |
| Disable touchscreen lock | `ba_notouchlock` (empty file) | `notouch` | locked |

Example: `BadApple_rows32_notouch.zip`.

Storage is searched in this order: `/external_sd`, `/sdcard1`, `/usb_otg`, `/usb-otg`, `/mnt/media_rw/*`, `/storage/*`, `/mnt/usb*`, any mounted vfat/exfat/sdfat/texfat/fuseblk/ntfs volume from `/proc/mounts`, then `/sdcard` and `/data/media/0`.

A log is written to `bad_apple_log.txt` in the first writable storage, and to `/tmp` otherwise. Attach it when reporting a problem.

## Touchscreen lock

The script looks for touch input devices in `/sys/class/input` (names matching common touch drivers, key and button devices are skipped) and writes to their `enabled` or `inhibited` node, plus `/sys/class/sec/tsp/input/enabled` on Samsung devices. The original values are saved and written back on exit. If no suitable node exists nothing is changed.

Some touch drivers may not recover cleanly after being disabled. If your touchscreen stays dead after playback, reboot the recovery, and use the `notouch` zip name or `ba_notouchlock` from then on. Holding the power button always works.

## Building

Python 3.8 or newer, standard library only.

```
python build.py
python build.py --calibration
```

Options for `build.py`:

- `--frames PATH` frame file, default `frames/frames.txt`
- `--output PATH` default `dist/BadApple_TWRP.zip`
- `--shell PATH` interpreter written to the shebang, default `/sbin/sh`
- `--content-rows N` rows per frame, default 19

The build adds an empty file named `cq61tech` to the zip. The installer refuses to run without it.

## Making frames

Requires `ffmpeg`, `numpy` and `Pillow`.

```
python tools/convert.py video.mp4
```

Options: `--cols` (default 52), `--rows` (default 19), `--fps` (default 15), `--cell-w` and `--cell-h` (default 6 and 12), `--black` and `--white` levels, `--font`, `--chars`, `--letterbox`.

For each cell the converter picks the character whose shape best matches the pixels, instead of mapping brightness to a character ramp. The console is about 54 columns wide on the reference device, so 52 columns fit with a margin. If you change `--rows`, pass the same value to `build.py --content-rows`.

## Troubleshooting

- Fails immediately with error 255: the recovery has no `/sbin/sh`. Rebuild with `--shell /system/bin/sh`.
- Lines wrap and the picture is broken: your console is narrower than 52 columns. Generate frames with a smaller `--cols`.
- Top of the picture is cut off: `ba_rows` is larger than the visible console height, or smaller than needed. Use the calibration zip.
- Plays too fast or too slow: change `ba_delay`. Larger is slower.
- Nothing is printed: check `bad_apple_log.txt`.

## Legal

The code in this repository is released under the MIT license. The song Bad Apple!! and the original animation belong to their respective authors and are not part of this repository. Generate frames from a video you are allowed to use, and check the rights before redistributing a zip that contains them.
