# Agent install guide

Instructions for an AI coding agent (Claude Code, Codex, Cursor, …) that a user has asked to apply the
fixes in this repository to their machine. The human-readable explanation of every fix is in
[README.md](README.md); read it first. This file says **how to apply them safely**.

## Ground rules

1. **Ask before anything that runs as root or changes the system** (`sudo`, files under `/etc` or
   `/usr`, DKMS, kernel modules, initramfs). Show the exact commands first. One confirmation covers one
   fix, not the whole plan.
2. **The user types their own password.** Never ask for it in chat, never pipe it into `sudo`, never
   create passwordless sudo rules. If your environment can't show an interactive `sudo` prompt, give the
   user the commands to run (in Claude Code they can prefix a command with `! ` to run it in-session).
3. **Only apply fixes the machine needs.** Detect first. Skip a fix when its hardware is missing, the
   problem isn't present, or an equivalent setting already exists, and say why.
4. **Back up before overwriting.** Copy any existing target to `<file>.bak-<date>` first. Keep a list of
   every file you create or change. You will print it at the end as the rollback list.
5. **Audio safety.** Built-in speakers on this model can be damaged. Keep any test playback at ≤ 30 %
   volume, prefer headphones or an external speaker, and never route a live microphone to the speakers.
6. **Don't reboot, suspend, or switch GPUs without asking.** The black-screen rescue switches the panel
   between GPUs. Don't run it as a test; `--diag-only` is the safe check.
7. **Report honestly.** If a check fails or a step was skipped, say so with the output. Statuses in the
   README ("Works", "untested", "Open") are part of the contract: don't upgrade them in your summary.

## Phase 1 — Inventory (read-only, no confirmation needed)

Run and record:

```bash
cat /sys/class/dmi/id/product_name            # expect MacBookPro13,3
grep -E '^(ID|ID_LIKE|VERSION_ID)=' /etc/os-release
uname -r
lspci -nn | grep -Ei 'vga|network|usb controller'
lsusb | grep -i apple
grep -h '^Codec' /proc/asound/card*/codec#* 2>/dev/null
lsmod | awk '{print $1}' | grep -E '^(apple_gmux|applespi|apple_ib_tb|apple_ibridge|brcmfmac|hid_apple|snd_hda_codec_cs8409)$'
dkms status 2>/dev/null
ls /etc/modprobe.d /etc/modules-load.d /etc/udev/rules.d
command -v hyprctl yay paru pacman mkinitcpio dracut wireplumber 2>/dev/null
```

- The stock `snd_hda_codec_cs8409` name is kept by the replacement driver, so detect
  snd-hda-macbookpro with `dkms status`, not `lsmod`.
- **Model gate:** this repo targets `MacBookPro13,3`. For other `MacBookPro13,x` / `14,x` models, tell
  the user that only some fixes may apply and which ones you think do. For anything else, stop.
- **Distro gate:** commands assume Arch Linux (pacman, AUR helper, mkinitcpio). On other distributions,
  translate package and initramfs steps and tell the user you are doing so.

## Phase 2 — Decide and propose

For each fix, decide **apply / skip / ask the user**, using the table. Then show the user one plan:
fix, reason, files touched, whether root is needed. Wait for their go-ahead.

| Fix | Applies when | Ask the user? |
|---|---|---|
| Wi-Fi | `brcmfmac` loaded with BCM43602 `[14e4:43ba]`, and no `feature_disable` already in `modprobe -c \| grep brcmfmac` | Ask whether WPA networks reject correct passwords; skip if Wi-Fi works fine |
| Touch Bar | `lsusb` shows `05ac:8600 iBridge` and `apple_ib_tb` is not loaded | Yes: needs building a driver |
| Keyboard at boot | disk is encrypted and no `applespi` in the mkinitcpio config | Yes |
| Fn keys (external Apple keyboard) | the user uses an external Apple keyboard | Yes: it's a preference |
| USB-C hotplug | `lspci -d 8086:15d4` lists the JHL6540 controller(s) | Ask whether late-plugged USB-C devices go undetected |
| Audio | codec `CS8409` present and the speakers/mic don't work, or `snd-hda-macbookpro` already installed | Yes: driver build; also ask whether they use the 3.5 mm jack |
| Black-screen rescue | `apple_gmux` loaded and Hyprland in use | Ask whether they get "backlight on, black screen" |
| Bluetooth calls | the user wants phone calls through the laptop (PipeWire + WirePlumber) | Yes |
| Suspend | — | Never "fix": it's open. Only explain the README section |

## Phase 3 — Apply (one fix at a time)

For every fix: back up targets → install → verify → record changed files. If verification fails, stop
that fix, show the output, and offer to roll it back before going on.

### Wi-Fi
- Install `wifi/brcmfmac.conf` to `/etc/modprobe.d/brcmfmac.conf`.
- Reload: `sudo modprobe -r brcmfmac && sudo modprobe brcmfmac` (this drops Wi-Fi briefly; warn the user
  if they're connected over Wi-Fi only, or let them reboot later instead).
- Verify: `modprobe -c | grep 'brcmfmac feature_disable=0x82000'`; then the user reconnects to the
  network that was failing.

### Touch Bar
- Needs `base-devel`, kernel headers matching `uname -r` (`linux-headers` or the distro's equivalent) and
  `dkms`. Ask before installing packages.
- Follow the README steps exactly: clone `roadrunner2/macbook12-spi-driver` branch
  `touchbar-driver-hid-driver`, apply `touchbar/apple-ibridge-kernel-7.patch`, copy the sources plus
  `touchbar/dkms.conf.example` → `dkms.conf` and `touchbar/Kbuild.example` → `Kbuild` into
  `/usr/src/apple-ibridge-1.0/`, then `sudo dkms install apple-ibridge/1.0`.
- If the patch doesn't apply or the build fails on a newer kernel, stop and show the compiler errors. Do
  not improvise kernel code changes without telling the user exactly what you changed.
- Install `touchbar/apple-ibridge.conf` → `/etc/modprobe.d/`, and
  `touchbar/modules-load-apple-ibridge.conf` → `/etc/modules-load.d/apple-ibridge.conf`. Also install
  `touchbar/mkinitcpio-apple_ibridge.conf` → `/etc/mkinitcpio.conf.d/apple_ibridge.conf` (loads the
  driver early so it wins the iBridge over `hid_sensor_hub`) and run `sudo mkinitcpio -P`. On other
  initramfs tools (dracut, booster) translate it and say so.
- Verify after a reboot (ask first): `lsmod | grep apple_ib_tb`, `lsmod | grep hid_sensor_hub` is empty,
  and the user sees keys on the Touch Bar.

### Keyboard at boot (encrypted disk)
- Only if the disk is encrypted and `grep -rs applespi /etc/mkinitcpio.conf /etc/mkinitcpio.conf.d/`
  finds nothing (Omarchy already has it): install `keyboard/mkinitcpio-macbook_spi_modules.conf` →
  `/etc/mkinitcpio.conf.d/macbook_spi_modules.conf`, `sudo mkinitcpio -P`. **Ask first**, and make sure
  the user has another way to unlock if the next boot's keyboard doesn't work (external USB keyboard).

### Fn keys (external Apple keyboard)
- Install `keyboard/hid_apple.conf` → `/etc/modprobe.d/`. Verify after replug/reboot:
  `cat /sys/module/hid_apple/parameters/fnmode` → `2`. It does not affect the built-in keyboard or
  Touch Bar.

### USB-C hotplug
- Install `usb-c/tb-usb-power` → `/usr/local/bin/` (mode 755), `usb-c/90-tb-usb-power.rules` →
  `/etc/udev/rules.d/`, then `sudo udevadm control --reload` and `sudo /usr/local/bin/tb-usb-power`.
- Verify on AC: every `lspci -d 8086:15d4` device has `power/control` = `on`
  (`cat /sys/bus/pci/devices/<addr>/power/control`); on battery = `auto`. The rule matches power supply
  `ADP1`: check `ls /sys/class/power_supply` and adapt the rule if the name differs.

### Audio
- Install the AUR package `snd-hda-macbookpro-dkms-git` with the user's AUR helper (ask first), or build
  [davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) per its README.
- If they use the 3.5 mm jack with a mic-less plug: enable `INTERNAL_MIKE_ONLY` in
  `/usr/src/snd-hda-macbookpro-*/Makefile` (exactly one `KBUILD_EXTRA_CFLAGS` line active, containing
  `-DINTERNAL_MIKE_ONLY`), then `dkms build … --force` **and** `dkms install … --force`. Verify the flag in
  `/var/lib/dkms/snd-hda-macbookpro/*/build/make.log`; `install` alone does not recompile.
- Copy `audio/mixer-paths/*` → `~/.config/alsa-card-profile/mixer/paths/` (user files, no root) and
  restart `wireplumber pipewire pipewire-pulse`.
- Check that no always-on echo-cancel module is configured:
  `grep -rl --include='*.conf' echo-cancel ~/.config/pipewire /etc/pipewire 2>/dev/null` (files ending in
  `.disabled` or similar are parked, not active). If one is, tell the user why it
  freezes playback (README) and offer to disable it. Don't delete their config.
- Verify (at low volume): `wpctl status` lists the internal speakers and mic; a 2-second
  `arecord -d 2 -f S16_LE -r 44100 /tmp/t.wav` succeeds with the jack plugged in; ask the user to confirm
  playback is audible and doesn't freeze.

### Black-screen rescue
- User files only: install `black-screen/display-rescue` and `black-screen/display-mux-rescue` to
  `~/.local/bin/` (755).
- Add a keybind that works while locked. Inspect the user's Hyprland config first (Lua config:
  `~/.config/hypr/*.lua`; classic: `hyprland.conf`), check the key isn't taken, and use the matching
  example from the README. Reload and check `hyprctl configerrors` is empty.
- Verify with `display-rescue --diag-only` (prints a log path; no display change). Explain the real
  flow: press the key when the screen is black, type the password blind, Enter, wait ~15 s.
- Root cause is unknown: say "workaround", not "fixed".

### Bluetooth calls
- Copy `bluetooth-calls/*.conf` → `~/.config/wireplumber/wireplumber.conf.d/`, restart `wireplumber`.
- Verify: `systemctl --user is-active wireplumber`; `wpctl status` still shows audio devices.
  `hfp-cvsd.conf` only matters once HFP calls are set up (beyond this repo).

## Phase 4 — Report

Finish with:

1. Each fix: applied / skipped (why) / failed (output), and its README status.
2. **Rollback list:** every file created or changed, with its backup path, and the commands to undo
   (remove the file or restore `.bak-*`, `sudo dkms remove <module>/<version> --all`, reload udev/modules).
3. Anything that needs a reboot or the user's own check (Touch Bar visible, Wi-Fi connects, audio).
