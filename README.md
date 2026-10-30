# webcam-als

**Automatic screen brightness on KDE Plasma, using your webcam as an ambient light sensor.**

Many laptops — including a lot of ThinkPads — ship without an ambient light sensor (ALS), so
Plasma's *"Automatically adapt to environment"* option never appears. This project works around
that limitation: it uses the built-in webcam as a light meter and adjusts the internal panel
brightness accordingly, relative to a **base brightness you choose**.

Tested on a Lenovo ThinkPad T480 (Intel UHD 620, `intel_backlight`) with KDE Plasma 6.8 / Wayland.

---

## Features

- **Webcam as a light sensor** — no ALS required.
- **Exposure lock per sample** — auto exposure is disabled for a single shot and restored
  immediately, so the camera is not left in manual mode for video calls.
- **Wide dynamic range** — three exposure steps (15 ms / 40 ms / 125 ms) chosen automatically,
  normalized so the reading tracks ambient light instead of camera gain.
- **Base brightness** — in bright light the screen uses your base value; in the dark it is
  reduced by a configurable percentage (e.g. base 70%, max reduction 55% → 31% in the dark).
- **Self-calibrating** — after ~30 samples it learns the dark/bright extremes of your room
  (5th–95th percentile) and maps the log of illuminance onto brightness.
- **No on-screen OSD spam** — changes go through `SetBrightnessWithContext` with the
  `SuppressIndicator` flag, so Plasma does not pop up the brightness overlay every cycle.
- **Power-aware** — samples every 10 s on AC, every 30 s on battery; skips while the session is
  idle or while another program is using the camera.
- **Qt settings app** — base brightness, max reduction, floor, sampling intervals, on/off and
  optional autostart. Changes apply live, without restarting the daemon.

## Requirements

| Component | Why |
|---|---|
| Linux + KDE Plasma 6 (Wayland or X11) | `org.kde.ScreenBrightness` D-Bus API |
| Python ≥ 3.11 | runtime (stdlib only for the engine) |
| `ffmpeg` | frame capture from the webcam |
| `v4l-utils` | `v4l2-ctl`, exposure control |
| `busctl` (systemd) | D-Bus calls |
| PySide6 *(GUI only)* | settings app |

## Installation

```bash
git clone https://github.com/kkongiu/webcam-als.git
cd webcam-als
./install.sh
```

`install.sh` copies the scripts to `~/.local/bin`, the launcher to
`~/.local/share/applications`, and the systemd user unit to `~/.config/systemd/user` when that
directory is writable.

Manual installation is just as easy:

```bash
install -m755 src/webcam-als src/webcam-als-settings ~/.local/bin/
```

## Usage

### Settings app

```bash
webcam-als-settings
```

Also available in the application menu as **“Luminosità automatica (webcam)”**.
The interface is currently in Italian.

| Control | Meaning |
|---|---|
| **Base (piena luce)** | brightness used when the room is bright (10–100%) |
| **Riduzione al buio** | how much to subtract from the base in the dark (0–75%) |
| **Minimo assoluto** | hard lower bound (5–50%) |
| **Intervallo con alimentatore / a batteria** | sampling period in seconds |
| **Attiva ora** | start/stop the background daemon |
| **Avvia automaticamente all'accesso** | install/remove the autostart entry |
| **Misura ora** | take one measurement immediately |
| **Ricalibra** | forget the learned light range |

### Command line

```bash
webcam-als --status        # measure and print, without touching brightness
webcam-als --status --json # same, machine-readable
webcam-als --once          # one cycle, applies brightness
webcam-als --apply 60      # set brightness to 60% right now
webcam-als --reset         # clear learned calibration
webcam-als                 # run the daemon in the foreground
```

Stop a running daemon with `pkill -f 'bin/webcam-als$'` or via the app.

> **Alternative to the app's autostart checkbox:** if you prefer systemd, enable the user unit
> installed by `install.sh` with `systemctl --user enable --now webcam-als`.

## Configuration

`~/.config/webcam-als/config.json` (edited by the app, read by the daemon on every cycle):

| Key | Default | Description |
|---|---|---|
| `base_pct` | `70` | brightness in bright light (%) |
| `max_reduction_pct` | `55` | maximum reduction in the dark, relative to base |
| `floor_pct` | `10` | absolute minimum brightness (%) |
| `interval_ac` | `10` | seconds between samples on AC |
| `interval_battery` | `30` | seconds between samples on battery |
| `alpha` | `0.25` | smoothing factor (0 = frozen, 1 = instant) |
| `max_step` | `15.0` | maximum change per cycle (percentage points) |
| `deadband` | `2.0` | hysteresis: changes smaller than this are ignored |

Runtime state (last reading, learned range, PID) lives in
`~/.local/state/webcam-als/`, with a rotating log in `webcam-als.log`.

## How it works

1. **Lock exposure.** `auto_exposure` is switched to manual and a fixed
   `exposure_time_absolute` is set.
2. **Grab a few frames** at 320×180 in grayscale (PGM, parsed directly) and take the last one,
   so the sensor has settled.
3. **Adapt the exposure.** If the frame is nearly black the next longer exposure is used, if it is
   nearly white the next shorter one. The measured luma is then normalized to a common reference
   (`luma × factor(exposure)`), which keeps the reading proportional to ambient light.
4. **Restore auto exposure** in a `finally` block, so the camera is never left in manual mode.
5. **Map to brightness.** The normalized value is compared with the learned range
   (`lo`, `hi`) on a logarithmic scale; the result selects how much of `max_reduction_pct`
   is subtracted from `base_pct`.
6. **Smooth and apply.** EMA smoothing (`alpha`), a per-cycle cap (`max_step`) and a deadband
   avoid flicker and needless D-Bus traffic. Changes are sent to
   `org.kde.ScreenBrightness` with `flags = 0x1` (`SuppressIndicator`), which tells PowerDevil
   not to show the brightness OSD.

## Limitations

- **The webcam must not be in use.** If a video call is running, the sample is skipped.
- **Auto exposure is briefly disabled** (≈0.3 s every 10 s). Modern conferencing software
  re-adapts instantly, but on some cameras you may notice a short flicker.
- **The camera is not a calibrated lux meter.** Absolute lux values are meaningless; only the
  relative change matters. Two-point calibration is learned automatically over time.
- **Manual brightness changes are overridden** within one sampling interval — that is the point
  of the tool. Turn it off from the app when you want full manual control.
- **External monitors** are not handled (only the internal panel via `backlight`).
- **Plasma's idle dimming** still works, but a subsequent automatic adjustment may restore
  brightness while you are away; the daemon pauses when the session reports idle.

## Uninstall

```bash
rm ~/.local/bin/webcam-als ~/.local/bin/webcam-als-settings
rm ~/.local/share/applications/webcam-als-settings.desktop
rm -f ~/.config/autostart/webcam-als.desktop
rm -rf ~/.config/webcam-als ~/.local/state/webcam-als
```

## License

MIT — see [LICENSE](LICENSE).
