# Linux on the MacBook Pro 15" 2016 (MacBookPro13,3)

Fixes and workarounds collected while running [Omarchy](https://omarchy.org/) (Arch Linux + Hyprland)
on a **MacBookPro13,3**: 15-inch, 2016, four Thunderbolt 3 ports, Touch Bar (T1), Intel Core i7-6820HQ
(Skylake, HD Graphics 530) + **AMD Radeon Pro 450/455/460** (Baffin/Polaris 11), Cirrus Logic **CS8409**
audio, Broadcom **BCM43602** Wi-Fi, UART Broadcom Bluetooth (BCM2E7C).

Most of this also applies to other Arch-based distributions, and parts of it to the 13-inch 2016/2017 and
15-inch 2017 models (MacBookPro13,x / 14,x). Check your model with `cat /sys/class/dmi/id/product_name`.

Tested on kernel 7.2 (Omarchy 4.0.6), November 2026. Each section says how well it is proven.

| Area | Symptom | Fix | Status |
|---|---|---|---|
| [Wi-Fi](#wi-fi-wpa-password-rejected) | WPA2 networks reject a correct password | brcmfmac option | Works |
| [Touch Bar](#touch-bar) | Touch Bar blank / no function keys | apple-ibridge driver + blacklist | Works |
| [Keyboard](#fn-keys) | F1–F12 act as media keys | `hid_apple fnmode=2` | Works |
| [USB-C](#usb-c-hotplug) | USB-C devices not detected when plugged in later | keep TB3 USB controller awake on AC | Works |
| [Audio](#audio-cs8409) | No speakers/mic, mic breaks with a jack plugged in, playback freezes | snd-hda-macbookpro built with `INTERNAL_MIKE_ONLY`; no always-on echo-cancel | Works |
| [Black screen](#black-screen-backlight-on) | Backlight on, picture black after idle lock / resume | rescue key (gmux flip + link retrain) | Partial: recovered once |
| [Suspend](#suspend-s3) | Never resumes from S3 | none yet | Open |
| [Bluetooth calls](#bluetooth-phone-calls-hfp) | Robotic call audio; WirePlumber killed when a call starts | CVSD instead of mSBC; non-RT data loop | Works |

> **Protect the speakers.** On this machine the built-in speakers were damaged (they now buzz even
> during the startup chime). Likely causes: a microphone → speaker feedback loop during a call test
> without echo cancellation, and/or loud bass with no speaker protection under Linux. Test audio at low
> volume, and never route a live mic to the built-in speakers.

---

## Wi-Fi: WPA password rejected

Broadcom's in-firmware supplicant/authenticator fails the WPA four-way handshake on this Apple hardware;
it shows up as "wrong password". Let `wpa_supplicant`/`iwd` do the handshake instead:

```bash
sudo cp wifi/brcmfmac.conf /etc/modprobe.d/
sudo modprobe -r brcmfmac && sudo modprobe brcmfmac   # or reboot
```

## Touch Bar

The Touch Bar (T1 "iBridge") needs the out-of-tree `apple-ibridge` driver by Ronald Tschalär
(`apple-ibridge`, `apple-ib-tb`, `apple-ib-als`; GPL-2.0), from
[roadrunner2/macbook12-spi-driver](https://github.com/roadrunner2/macbook12-spi-driver) (branch
`touchbar-driver-hid-driver`), installed with DKMS. Upstream no longer builds on current kernels;
`touchbar/apple-ibridge-kernel-7.patch` updates it for the newer kernel APIs (void `remove` callbacks,
const `report_fixup`, `iio_device_alloc`/`iio_trigger_alloc` changes) and builds on 7.2:

```bash
git clone -b touchbar-driver-hid-driver https://github.com/roadrunner2/macbook12-spi-driver
cd macbook12-spi-driver && patch -p1 < /path/to/touchbar/apple-ibridge-kernel-7.patch
sudo mkdir -p /usr/src/apple-ibridge-1.0
sudo cp apple-ibridge.[ch] apple-ib-tb.c apple-ib-als.c LICENSE /usr/src/apple-ibridge-1.0/
sudo cp /path/to/touchbar/dkms.conf.example /usr/src/apple-ibridge-1.0/dkms.conf
sudo cp /path/to/touchbar/Kbuild.example /usr/src/apple-ibridge-1.0/Kbuild
sudo dkms install apple-ibridge/1.0
```

`hid_sensor_hub` claims the iBridge HID interface that carries the Touch Bar display controls before
`apple-ibridge` can, so blacklist it (its only user here is the ambient light sensor, which `apple-ib-als`
handles), and load the Touch Bar module at boot:

```bash
sudo cp touchbar/apple-ibridge.conf /etc/modprobe.d/
sudo cp touchbar/modules-load-apple-ibridge.conf /etc/modules-load.d/apple-ibridge.conf
sudo mkinitcpio -P    # if hid_sensor_hub is in your initramfs
```

## Fn keys

`keyboard/hid_apple.conf` sets `fnmode=2`: F1–F12 are function keys, Fn+F-key gives the media action.

```bash
sudo cp keyboard/hid_apple.conf /etc/modprobe.d/
```

## USB-C hotplug

The Intel JHL6540 Thunderbolt 3 USB controller (Alpine Ridge, PCI `8086:15d4`) runtime-suspends and then
misses devices plugged in later. `usb-c/tb-usb-power` keeps it awake on AC and lets it power-save on
battery; the udev rule runs it on AC changes and when the controller appears.

```bash
sudo install -m755 usb-c/tb-usb-power /usr/local/bin/
sudo cp usb-c/90-tb-usb-power.rules /etc/udev/rules.d/
sudo udevadm control --reload
tb-usb-power on      # manual override (as root), e.g. on battery before plugging something in
```

## Audio (CS8409)

The in-kernel driver gives no usable output on this Mac. Use
[davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) (Arch: AUR
`snd-hda-macbookpro-dkms-git`).

**Mic stops working, or the whole card stalls, when something is plugged into the 3.5 mm jack.**
With a mic-less plug (headphones, a powered speaker) the driver never set up capture: `arecord` failed
with EIO and any mic use stalled the card. Build the driver with `INTERNAL_MIKE_ONLY` so the built-in
mic is always the capture device:

```bash
sudo sed -i.orig 's/^#\(KBUILD_EXTRA_CFLAGS = "-DINTERNAL_MIKE_ONLY\)/\1/' /usr/src/snd-hda-macbookpro-0.1/Makefile
# make sure only the INTERNAL_MIKE_ONLY line is active (comment out the other KBUILD_EXTRA_CFLAGS line)
sudo dkms build snd-hda-macbookpro/0.1 --force && sudo dkms install snd-hda-macbookpro/0.1 --force
grep INTERNAL_MIKE_ONLY /var/lib/dkms/snd-hda-macbookpro/0.1/build/make.log   # confirm the flag was used
```

`dkms install` alone does **not** recompile, so check `make.log`. Re-apply after a package update
rebuilds the module without the flag.

Then keep PipeWire/PulseAudio from switching the internal mic off when the jack is in, with the mixer
path override in `audio/mixer-paths/` (derived from PulseAudio's file, LGPL-2.1):

```bash
mkdir -p ~/.config/alsa-card-profile/mixer/paths
cp audio/mixer-paths/* ~/.config/alsa-card-profile/mixer/paths/
systemctl --user restart wireplumber pipewire pipewire-pulse
```

Other things learned the hard way:

- **Don't keep `libpipewire-module-echo-cancel` loaded all the time.** It holds the built-in mic open,
  the mic then drives the CS8409's clock, and speaker/jack playback never starts: apps freeze on "play".
  Load echo cancellation only for the duration of a call.
- The codec only supports **44.1 kHz**.
- Don't use the HDA `reconfig` sysfs reset on this codec: probe fails (-22) and the card is gone until reboot.

## Black screen, backlight on

The backlight is driven by gmux, so "backlight on" says nothing about the GPU. Two separate failures:

1. **After S3 resume:** amdgpu fails to come back (`SMU load firmware failed`,
   `amdgpu_device_ip_resume failed (-22)`). See [Suspend](#suspend-s3).
2. **After an idle lock (no suspend), occasionally** (~2 in 60 locks here): the picture goes black and
   stays black after unlocking. The compositor is healthy (`grim` captures a correct frame), DPMS is on,
   the eDP link reports trained (DPCD lanes locked, sink in sync), no kernel errors, and a text console
   (`chvt 2`) is black too, so it isn't Hyprland. A DPMS off/on cycle, a forced modeset and an eDP link
   retrain alone did **not** help.

   **What recovered it (once):** switching the panel to the Intel GPU through gmux and back
   (`vgaswitcheroo` `MIGD` then `MDIS`), then retraining the eDP link, then a DPMS cycle, in that order.

`black-screen/display-rescue` automates this for a blind screen. Bind it to a key that works while the
session is locked. It saves diagnostics to `~/.local/state/display-rescue/` (the Hyprland log is on
tmpfs and is lost on the reboot you would otherwise need), opens a focused `sudo` prompt for
`display-mux-rescue` (type your password blind), then cycles DPMS. Wait about 15 s.

```bash
install -m755 black-screen/display-rescue black-screen/display-mux-rescue ~/.local/bin/
# Hyprland (Lua config):
#   o.bind("SUPER + CTRL + ALT + P", "Rescue black display", os.getenv("HOME") .. "/.local/bin/display-rescue", { locked = true })
# classic hyprland.conf:
#   bindl = SUPER CTRL ALT, P, exec, ~/.local/bin/display-rescue
display-rescue --diag-only   # records state only, safe to try
```

Root cause unknown. If you find it, please open an issue.

## Suspend (S3)

Not solved. In 13 attempts S3 never resumed cleanly; the logged resumes failed in amdgpu SMU firmware
load (same failure seen after a VCE hang during screen recording). Untested next step: `s2idle`
(`mem_sleep_default=s2idle` on the kernel command line). Until then, hibernate or don't suspend.

## Bluetooth phone calls (HFP)

Using the Mac as a hands-free kit for a phone (PipeWire/WirePlumber with `bluez5` telephony):

- **mSBC (wideband) call audio was robotic, choppy and echoey** on this Mac's UART Broadcom adapter
  (`hci_uart_bcm`, BCM2E7C). Plain CVSD (8 kHz) is clear: `bluetooth-calls/hfp-cvsd.conf`. That the
  adapter link is the cause is a theory; forcing `clock.force-quantum = 960` did not help.
- **WirePlumber was SIGKILLed the moment call audio started.** RTKit gave its data loop real-time
  priority while its `RLIMIT_RTTIME` was 0. `bluetooth-calls/no-realtime-data-loop.conf` runs
  WirePlumber's data loop at normal priority (PipeWire's own threads stay real-time).
- For call audio, use a node latency that is a multiple of 10 ms (`960/48000`): quanta like 1024 caused
  ~3 xruns/s and garbled audio.
- The built-in mic is boxy (300–600 Hz) and picks up fan hiss; WebRTC noise suppression helps, EQ didn't.

```bash
mkdir -p ~/.config/wireplumber/wireplumber.conf.d
cp bluetooth-calls/*.conf ~/.config/wireplumber/wireplumber.conf.d/
systemctl --user restart wireplumber
```

---

Contributions welcome, especially for suspend, the black screen root cause, and other MacBookPro13,x/14,x
models. Scripts and documentation are MIT-licensed (see `LICENSE`); `audio/mixer-paths/` is derived from
PulseAudio and stays under LGPL-2.1.
