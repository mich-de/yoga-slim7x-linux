# Linux on the Lenovo Yoga Slim 7x (83ED, Snapdragon X Elite)

A working kit, and the notes behind it, for running **Fedora 45 KDE (aarch64)** on the Lenovo Yoga Slim 7x 14Q8X9.

It contains three things:

1. **A self-contained USB stick** that boots Fedora with keyboard, touchpad and audio working, with no network and no commands to type.
2. **Reverse-engineering notes and tools** for the Windows audio stack of this laptop: speaker tuning, amplifier settings, speaker protection, Dolby.
3. **Audio Yoga**, an app that gives Fedora the audio profiles the laptop has under Windows, by running the laptop's own Dolby libraries inside PipeWire.

Status date: 2026-11-17. Everything here was done and measured on **one** laptop. A second unit is exactly what the project needs: see [Working together](#working-together).

> **Private repository. Do not make it public as it is.** It holds proprietary files copied from this laptop's Windows installation (Qualcomm firmware, Windows audio drivers, calibration data, Dolby tuning files) and logs with hardware identifiers. See [Proprietary content](#proprietary-content).

> **Language.** This file is the only one in English. Scripts, comments, file names and the other documents are in Italian. There is a [glossary](#glossary) at the end.

## Contents

- [Status at a glance](#status-at-a-glance)
- [Hardware](#hardware)
- [Repository layout](#repository-layout)
- [The USB stick](#the-usb-stick)
- [Keyboard and touchpad](#keyboard-and-touchpad)
- [Firmware and coprocessors](#firmware-and-coprocessors)
- [Audio](#audio)
- [Speaker protection](#speaker-protection)
- [Audio Yoga](#audio-yoga)
- [Display, webcam, Secure Boot, other distributions](#display-webcam-secure-boot-other-distributions)
- [Reverse-engineering notes and tools](#reverse-engineering-notes-and-tools)
- [Proprietary content](#proprietary-content)
- [Safety rules](#safety-rules)
- [Working together](#working-together)
- [Open items](#open-items)
- [Glossary](#glossary)
- [Credits and licences](#credits-and-licences)

## Status at a glance

Fedora KDE Live 45-1.4 aarch64, kernel 7.2.11-300.fc45.aarch64, booted from the USB stick with the default menu entry. Fedora has **not** been installed to the internal disk yet.

| Area | Status | Notes |
|---|---|---|
| Keyboard, touchpad (gestures) | Works with the kit | The I2C bus must run at 100 kHz. Fixed inside the kernel the stick boots. Confirmed on cold boots. |
| Touchscreen | Works | |
| Display, backlight, GPU | Works | Adreno X1-85 render node, firmware loads. |
| Wi-Fi | Works | |
| Bluetooth | Controller detected | Not tested further. |
| Battery, thermal sensors | Work | Battery reporting needs the ADSP firmware. |
| CPU frequency scaling | Works with the kit | Fedora does not load `scmi-cpufreq` by itself. ¹ |
| ADSP and CDSP coprocessors | Run with the kit | Fedora lacks `cdsp_dtbs.elf`. ¹ |
| Speakers | Work, quieter than Windows | See [Audio](#audio). |
| Internal microphones | Work | Used for every acoustic measurement here. Not reliable above 8 kHz. |
| Audio profiles (Dolby) | Work through Audio Yoga | Needs files from your own Windows installation. ¹ |
| Speaker protection | Demonstrated in tests | Not enabled for daily use. |
| Webcam | Does not work | The device tree lacks the camera nodes. |
| TPM | Not available | |
| Suspend | Offered by the kernel | Resume not characterised: the RTC is not a wake source, so it could not be tested automatically. |
| Secure Boot | Must be disabled | The patched kernel and the modules are unsigned. |
| Installed system | Not tested | The post-install automation has only run in a virtual machine. |

¹ Applied to the running system and added to the boot automation on 2026-11-17. The first cold boot with these changes is still to be checked.

The summary above comes from `strumenti/1-DIAGNOSTICA.sh`, which runs on any distribution and prints one `[OK]` / `[KO]` line per item.

## Hardware

| | |
|---|---|
| Model | Lenovo Yoga Slim 7x 14Q8X9, machine type 83ED |
| SoC | Snapdragon X Elite X1E-78-100 (12 cores), Adreno X1-85 GPU |
| Memory, storage | 32 GB, 1 TB NVMe |
| Display | 2944×1840 OLED touch panel (EDID `LEN 8AC2`) |
| Audio | 4 speakers (2 woofers, 2 tweeters), 4 Qualcomm WSA884x amplifiers on SoundWire, ADSP running AudioReach |
| Camera | OV02C10 sensor |
| Firmware | BIOS NHCN62WW (2025-02-12) |
| Windows audio identifiers | subsystem `IDEA4001`; Dolby DAX3 libraries 3.30812.891.0 |

## Repository layout

| Path | Contents |
|---|---|
| `README.md` | This file. |
| `HANDOFF.md` | The full work log in chronological order: causes found, measurements, decisions, failed attempts, next steps. Numbered sections; later sections override earlier ones. |
| `handover.md` | Short current state, one paragraph per work session. |
| `memory.md` | Stable facts, decisions and constraints. Read this first if you read Italian. |
| `strumenti/` | **The kit**: an exact copy of the `STRUMENTI` partition of the USB stick. Index: `strumenti/LEGGIMI.txt`. |
| `chiavetta-efi/` | GRUB menu of the stick (`grub.cfg`), the extra initrd (`strumenti.cpio`), its source tree (`initrd/`) and builder (`mk_cpio.py`). |
| `sorgenti/windows/` | PowerShell scripts used from Windows to write the ISO, create the kit partition and update the EFI partition. |
| `sorgenti/vm/` | Test of the stick image in a virtual machine (QEMU inside WSL). |
| `sorgenti/analisi/` | Device tree extraction from a kernel image, initrd listing, device tree diff. |

Inside `strumenti/`:

| Path | Contents |
|---|---|
| `1-DIAGNOSTICA.sh` … `12-TASTIERA-FIX-PERMANENTE.sh` | Manual commands, for when something does not start by itself. Listed in `LEGGIMI.txt`. |
| `avvio/` | The automation: `autorun-root.sh` (live session, as root), `audio-sistema.sh`, `audio-yoga.sh`, `audio-ampli.sh`, `utente-login.sh` (at user login), `dopo-anaconda.sh` (end of installation), `menu-utente.sh` (graphical menu). |
| `boot/` | Kernel 7.2.11 with the keyboard fix, copies of the GRUB menu and of the extra initrd. Menu entries and kernel parameters: `boot/LEGGIMI.txt`. |
| `fix-tastiera/` | Patched device tree and the `i2cslow2` module for fixing the keyboard on a running system. |
| `firmware/` | Qualcomm firmware taken from this laptop's Windows, with `SHA256SUMS` and `origine-windows.csv` (which driver package each file came from). |
| `audio/` | PipeWire and WirePlumber configuration, the `wsagain` module, files copied from Windows. |
| `audio/protezione/` | Speaker protection: DSP topology, patched `snd-q6apm`, helper modules, test scripts, amplifier register profile. |
| `audio/dolby/` | Audio Yoga sources. |
| `audio-auto/` | LADSPA plugins for offline installation, the Windows audio reverse-engineering report, the Dolby study. |
| `tools/` | `patch-dtb-i2c100k.py`, `misura-audio.py` (acoustic measurements), `ctl-amplificatori.sh`, `re-audio/` (ACDB, registry and tuning decoders). |
| `upstream/` | Kernel patch and report for the keyboard problem. **Not sent yet.** |
| `secureboot/`, `windows/` | Secure Boot procedure and certificates; PowerShell scripts (write an ISO to USB, Secure Boot state). |
| `docs/ALTRE-DISTRO.md` | What other distributions (Ubuntu, Debian, Arch) need on this laptop. |
| `schermo/` | Notes on the factory colour profiles of the panel (the profiles themselves are not tracked). |
| `pacchetti/`, `ucm/`, `dtb/` | Fedora packages for offline use, ALSA UCM profiles, the original device tree. |
| `log/`, `diag-*`, `riepilogo-*`, `esito-*` | Diagnostic output. |
| `vecchi/` | Superseded scripts. |

## The USB stick

### Layout

| Partition | Contents |
|---|---|
| 1 | `Fedora-KDE-Desktop-Live-45-1.4.aarch64.iso` written raw (sha256 `46a73d4c0a82a77551311ab1589255ecac51b5ce311b4fc84577f5ede5a44f5c`). Not included here. |
| 2 | The ISO's EFI partition (FAT, 30 MB): `EFI/BOOT/grub.cfg` replaced by `chiavetta-efi/grub.cfg`, plus `/strumenti.cpio`. |
| 3 | `STRUMENTI` (FAT32, 4 GB), created in the free space after the ISO: the content of `strumenti/`. Mounted at `/run/strumenti` in the live session. |

### Building one

1. Write the ISO raw to the USB disk and verify it: `strumenti/windows/scrivi-iso-su-usb.ps1` (it erases the disk; it refuses to write without `-Conferma`). On Linux, `dd` does the same.
2. Create the `STRUMENTI` partition (FAT32) in the free space after the ISO, with `sorgenti/windows/mkstrumenti.ps1`, then copy the content of `strumenti/` into it.
3. Update the EFI partition: copy `chiavetta-efi/grub.cfg` to `EFI/BOOT/grub.cfg` and `strumenti.cpio` to the root: `sorgenti/windows/esp-patch5.ps1`.

The scripts in `sorgenti/windows/` carry safety checks tied to the author's USB drive (model and size). Read and adapt them before running. Do not use Ventoy: it is not signed for ARM64 and its GRUB2 mode fails with `invalid magic number`.

### Boot menu

GRUB uses the US keyboard layout.

| Entry | What it boots |
|---|---|
| 1. `TUTTO AUTOMATICO (tastiera, touchpad, audio)` | Default. Patched kernel plus the automation (`enforcing=0`). |
| 2. `solo FIX TASTIERA (senza automatismi)` | Patched kernel, nothing else. |
| 3. `FIX TASTIERA con device tree esterno` | Stock kernel plus a `devicetree` line. May have no effect. |
| 4. `senza fix` | The ISO entry with the X Elite parameters. Then run `5-FIX-TASTIERA-SUBITO.sh`. |
| 5. `TUTTO AUTOMATICO - messaggi di avvio visibili` | Like 1 without `quiet rhgb`. |
| 6. Original ISO entry | No extra parameters. |

A submenu adds a `nomodeset` variant of the keyboard fix and the ISO's original menu. The default entry starts after 15 seconds.

Kernel parameters, from Fedora's guide for Snapdragon laptops:

| Parameter | Why |
|---|---|
| `clk_ignore_unused pd_ignore_unused` | Always needed on X Elite and X Plus laptops. |
| `systemd.tpm2_wait=0` | Avoids a 90-second wait for the TPM. |
| `modprobe.blacklist=qcom_q6v5_pas` | Recommended for booting from USB-C. With it the ADSP still ran and audio worked in the live session. Removed on the installed system. |
| `enforcing=0` | Live session only: the files injected by the extra initrd need SELinux permissive. The installed system keeps SELinux enforcing. |

### How the automation works

1. `strumenti.cpio` is an extra initrd holding an `/updates` folder. Fedora's live initramfs copies its content into the booted system (dracut's `20-apply-live-updates.sh`).
2. That content is small: a `strumenti.service` unit with its mount helper, a user autostart entry, a menu launcher and an Anaconda post-script. All the logic lives on the `STRUMENTI` partition, so it can change without rebuilding the cpio.
3. At boot the service mounts `STRUMENTI` at `/run/strumenti` and runs `avvio/autorun-root.sh` as root. It loads `scmi-cpufreq`, installs the CDSP firmware and starts the CDSP, installs the speaker setup and Audio Yoga, sets the amplifier gains, opens Windows volumes whose BitLocker key is stored in clear on the disk, and after about a minute saves a diagnostic report in `log/`.
4. At login `avvio/utente-login.sh` makes "Audio Yoga" the default output, or "Altoparlanti potenziati" if Audio Yoga is not there.
5. When Fedora is installed with the installer, the post-script runs `avvio/dopo-anaconda.sh` on the new system: patched kernel, a hook that patches future kernels, audio, firmware, kernel parameters.

Three things learnt the hard way:

- systemd applies Fedora's presets at first boot and removes `*.wants` symlinks. Units are enabled with `Wants=` drop-ins instead.
- Never add `lib/...` entries to the cpio: in the initramfs `lib` is a symlink to `usr/lib` and would be replaced.
- Rebuild the cpio with `python3 mk_cpio.py initrd strumenti.cpio` in `chiavetta-efi/`. The version on the stick also carries the two CDSP firmware files under `usr/lib/firmware/updates/`; that tree is not tracked.

## Keyboard and touchpad

**Cause.** The official device tree runs the bus `/soc@0/geniqup@bc0000/i2c@b80000` at 400 kHz. On this laptop (BIOS NHCN62WW) the keyboard controller at address `0x3a` cannot keep up: corrupted data, SDA held low, `-110` timeouts. The keyboard does not start and it blocks the touchpad, which sits on the same bus.

**Fix.** Run the bus at 100 kHz. Four forms of the same fix:

| Where | How |
|---|---|
| USB stick | `strumenti/boot/linux-7.2.11-300.fc45-kbd100k.efi`: Fedora's kernel with the embedded device tree patched in place. Three bytes differ from the original. Its signature is no longer valid. |
| Any device tree or kernel image | `strumenti/tools/patch-dtb-i2c100k.py`. |
| Running system | `strumenti/5-FIX-TASTIERA-SUBITO.sh` with `fix-tastiera/i2cslow2.ko`: changes the property in memory, then re-binds `geni_i2c` on `b80000.i2c`. |
| Installed Fedora | `strumenti/12-TASTIERA-FIX-PERMANENTE.sh`: patches the device tree inside the kernels in `/boot` and installs a hook for future kernels. |

A kernel patch and a report for `linux-arm-msm` are ready in `strumenti/upstream/`. They have not been sent.

## Firmware and coprocessors

`strumenti/8-INSTALLA-FIRMWARE.sh` installs the Qualcomm firmware on any distribution, into `/usr/lib/firmware/updates/qcom/x1e80100/LENOVO/83ED/` (the `updates` folder takes precedence). The files come from this laptop's Windows driver store; names are the ones the device tree asks for.

| Files | Purpose |
|---|---|
| `qcadsp8380.mbn`, `adsp_dtbs.elf`, `adspr.jsn`, `adsps.jsn`, `adspua.jsn`, `battmgr.jsn` | ADSP: audio and battery management. |
| `qccdsp8380.mbn`, `cdsp_dtbs.elf`, `cdspr.jsn` | CDSP. Fedora 45 lacks `cdsp_dtbs.elf`, so the CDSP does not start without the kit. |
| `qcdxkmsuc8380.mbn` | GPU zap shader. |
| `qcvss8380.mbn`, `qcav1e8380.mbn` | Video and AV1. |

Fedora's own `qcom-firmware-extract` package (offline copy in `strumenti/pacchetti/fedora45/`) extracts the same files from a Windows partition.

## Audio

### How the laptop is wired

- Four speakers: two woofers and two tweeters, each on its own WSA884x amplifier. Two SoundWire buses (WSA and WSA2).
- The playback PCM has four channels: 0 and 1 are the woofers, 2 and 3 the tweeters.
- The woofers produce nothing below about 250 Hz. The tweeters are about 19 dB more sensitive at 2 kHz.

### Why Linux is quiet and dull

1. A stereo stream reaches channels 0 and 1 only, so the tweeters stay silent.
2. Mainline keeps the amplifiers near minimum gain on purpose, because there is no speaker protection. The machine driver `sound/soc/qcom/x1e80100.c` caps `Digital Volume` at 81 and `PA Volume` at 6, and the ALSA UCM profile resets `PA Volume` at every activation.

`PA Volume` value *v* means a gain of 21 − 1.5 × (31 − *v*) dB: 17 is 0 dB, 29 is 18 dB, 31 is 21 dB. The amplifier reads it only when the output restarts.

### What Windows does

- Amplifiers at **18 dB** (`PA Volume` 29), with a register profile for the 4 Ω load. Captured in `strumenti/audio/protezione/amplificatori/`.
- Speaker protection in the DSP, with voltage and current feedback from the amplifiers.
- Lenovo's speaker tuning in DSP module `0x0701000B`, parameter `0x0800137B` (crossover at 2400 Hz).
- Dolby DAX3 as an audio processing object in the Windows audio engine.

### What the kit installs

| Piece | File | Effect |
|---|---|---|
| Output "Altoparlanti potenziati" | `audio/50-yoga-altoparlanti.conf` | PipeWire filter chain: 180 Hz high-pass, compressor (3:1, +12 dB), limiter at −1.5 dBFS, Linkwitz-Riley crossover at 2.4 kHz that feeds the tweeters at −7 dB. Tuned from sweeps with `tools/misura-audio.py`: 1.7 to 1.9 dB of deviation between 400 Hz and 8 kHz. |
| Soft mixer | `audio/51-yoga-soft-mixer.conf` | WirePlumber rule: the system volume is applied in software and never drives the amplifiers' `PA Volume`. |
| Amplifier gain | `audio/wsagain.ko`, `avvio/audio-ampli.sh` | Lifts the driver cap and sets `PA Volume` to 18 on the woofers (+1.5 dB) and 16 on the tweeters (−1.5 dB). |
| Audio profiles | `audio/dolby/`, `avvio/audio-yoga.sh` | See [Audio Yoga](#audio-yoga). |

The LADSPA plugins (`sc4_1882`, `fast_lookahead_limiter_1913`, from swh-plugins) are in `audio-auto/ladspa/` and as an RPM in `pacchetti/`, so nothing is downloaded.

### Is it as loud as Windows? No

The signal processing can match Windows. The maximum level cannot, yet.

| | Linux with the kit | Windows |
|---|---|---|
| Amplifier gain, woofers | +1.5 dB | +18 dB |
| Peak voltage at digital full scale | about 1.65 V | about 11 V |
| Speaker protection | none in daily use | always on |

The difference is 16.5 dB of analogue gain. Digital make-up gain recovers part of it at moderate levels, but nothing can pass digital full scale. Reaching Windows levels means running the amplifiers at 18 dB, and that is only safe with speaker protection working all the time.

## Speaker protection

**Experimental. Not active in normal use.** Details: `strumenti/audio/protezione/LEGGIMI.txt` and section 9 of `strumenti/audio-auto/REVERSE-AUDIO-WINDOWS.md`.

### What Windows runs

- One `SP_RX` module (instance `0x411A`) and one `SP_VI` module (`0x4121`) for all four speakers.
- Voltage and current feedback at 8000 Hz, 32 bit, 4 channels.
- The resistance and temperature of each voice coil at calibration (R0, T0), kept in the registry under `Services\qcadcm\State\SpeakerProtectionInfo`.
- The real thermal limit is a target temperature per speaker (90 °C) inside `SP_RX` parameter `0x08001532`, with a maximum attenuation of 12 dB.

### What exists for Linux

| Piece | File |
|---|---|
| Topology with `SP_RX` and `SP_VI`, same instance numbers as Windows | `audio/protezione/topologia/` (`build.sh`) |
| `snd-q6apm` with a control link, tuning data loaded from a file, parameter read-back | `audio/protezione/kernel/q6apm-sp.patch`, built with `make BUILD=<dir>` |
| Swap between the stock driver and the patched one on a running system | `kernel/scambia.sh`, `kernel/gprport.c` |
| Voltage and current feedback while the module is loaded | `kernel/wsavi.c` |
| Tuning data file in the order Windows sends it | `tools/re-audio/acdb_prot_blob.py` (output not tracked: it holds this unit's R0 and T0) |
| Tests | `kernel/prova-vi.sh`, `kernel/prova-vi-18db.sh`, `kernel/prova-protezione.sh`, `kernel/statovi.py` |

Prebuilt modules are for kernel 7.2.11-300.fc45.aarch64 only.

### Why calibration kept failing, and what fixed it

Three conditions, all needed at once. They were found by reading the Windows driver `qcaucd8380.sys`.

1. **SoundWire `Offset2`.** The feedback ports 10 and 11 of the controller need `Offset2 = 0`. The device tree has `qcom,ports-offset2 = 0xff`, which makes voltage and current come from the same bit. A measured resistance near **2.02 Ω** is the signature of this fault.
2. **Sense gains.** Windows writes `ISENSE2` (`0x3021`) = `0x07` and `VSENSE1` (`0x3020`) = `0x67`. Linux leaves `0x27` and `0x87`, and rewrites them at every power-up.
3. **Amplifier gain.** The `SP_VI` tuning assumes 18 dB. Its pilot tone is at −40 dBFS (0.110 V peak expected, threshold 25 %). Below about 6 dB of gain the DSP never sees the pilot.

Calibration states read back from the DSP (parameter `0x080011F8` of `0x4121`): 1 feedback port stopped, 2 warming up, 3 running, 4 **succeeded**, 5 failed, 6 waiting for feedback, 7 wait timed out, 8 feedback too low.

### Results on this laptop (2026-11-17)

All tests ran with the amplifiers at 18 dB, with the owner's consent for each one.

| Test | Result |
|---|---|
| Calibration, silence only | State 4. R0 = 3.840 / 3.594 / 4.218 / 3.983 Ω. Windows has 3.883 / 3.640 / 4.252 / 4.007 Ω: within 1.3 %. |
| Normal tuning (90 °C), 1 kHz at −20 dBFS on the woofers | Constant level, no attenuation. |
| Limit lowered to 30 °C, with feedback | Attenuates by about 11 dB. |
| Limit lowered to 45 °C, with feedback | Starts attenuated and is back at full level in 3 s: the DSP measures the coils at about 40 °C, below the limit. |
| Limit lowered, without feedback | Stays attenuated by about 12 dB: with no measurement the DSP assumes 50 °C. |
| Level and distortion | +22 dB over Linux's minimum gain. Distortion 0.2 to 1.7 % on the woofers, 1.8 to 2.6 % on the tweeters. No amplifier fault in the kernel log. |

So the thermal limiter works, and with feedback it follows the measured temperature. **Not tested:** excursion protection, levels above −20 dBFS, long use.

### What is missing for daily use

- The Windows power-stage register profile applied to the amplifiers.
- A service that brings up the feedback path whenever playback starts.
- Tests above −20 dBFS, raised in steps.
- The speaker chain retuned for the new gain.
- `qcom,ports-offset2 = 0` in the device tree, instead of patching kernel structures at run time.

## Audio Yoga

Audio profiles for the speakers, on Fedora. Details and limits: `strumenti/audio/dolby/LEGGIMI.md`. Design: `strumenti/audio-auto/dolby/PROGETTO.md`.

### What it is

The sound passes through the original code of the two Dolby libraries Windows uses on this laptop, with Lenovo's tuning for this model:

| Library | Role |
|---|---|
| `DolbyAPOVR.dll` | Content processing: profiles, virtual surround, dialogue enhancement, volume leveller. |
| `DolbyAPOvlldp150.dll` | Speaker processing: 20-band tuning curve, equaliser, multiband regulator that holds back loud sounds. |

```
applications
   │
   ▼
"Audio Yoga" output  (effect_input.audio_yoga, its own PipeWire instance: audio-yoga.service)
   │   DolbyAPOVR.dll ──► DolbyAPOvlldp150.dll        48 kHz, stereo, blocks of 256 samples
   ▼
"Altoparlanti (via Audio Yoga)"  (effect_input.yoga_spk_ay, in filter-chain.service)
   │   +6 dB, 2.4 kHz crossover, limiter at −1.5 dBFS, no compressor
   ▼
4-channel ALSA output ──► 4 × WSA884x ──► woofers and tweeters
```

The app (`audio_yoga.py`, PySide6) has six profiles (Dynamic, Movie, Music, Game, Voice, Off; Music is the default, as in Windows), a 20-band equaliser with presets, switches for surround, dialogue and volume leveller, "maximum volume" (+6 dB before the regulator) and a tray icon. Settings are kept in `~/.config/audio-yoga/stato.json`.

### How the libraries run on Linux

- `pe.c` maps the ARM64 Windows DLL into memory, applies its relocations and binds its imports: critical sections become no-ops, everything else a stub that reports its name if it is ever called. No Wine.
- The library's own functions are then called by address (`indirizzi.h`), with a small fake thread block in register `x18`.
- The files are **not modified**. They are accepted only if their SHA-256 is in the allow-list `audio-auto/dolby/dati/sha256-dll-yoga.txt`, because the addresses are valid for one build only.
- No licence or authenticity check is bypassed: these two libraries contain none. The Windows service `DAX3API.exe` is not needed.
- If the files are missing or not the expected ones, audio passes through unchanged.

### Private files

Audio Yoga needs four files that are **not** in this repository. They live in `dolby-privato/` on the kit partition.

| File | Where it comes from |
|---|---|
| `DolbyAPOvlldp150.dll`, `DolbyAPOVR.dll` | `C:\Windows\System32\DriverStore\FileRepository\dax3_swc_aposvc_arm64*\` on your own laptop. `avvio/audio-yoga.sh` copies them, read-only, if it can open the Windows volume. |
| `sha256-dll-yoga.txt` | Copy of the allow-list. |
| `profili.txt` | The tuning in the engine's format: `tools/re-audio/dolby_taratura.py <speaker xml> <headphone xml> out.json`, then `audio/dolby/profili.py out.json > profili.txt`. The XML files are in the `dax3_ext_qc` driver package; this unit uses `AUCD_DEV_0C29_SUBSYS_IDEA4001_ADCM_SUBSYS_IDEA4001.xml`. |

This is meant for personal use on the same hardware that carries the Windows licence.

### Build and test

```
cd strumenti/audio/dolby
make                                                 # needs gcc and ladspa-devel
./prova1 <dll folder> <hash list>                    # the original code runs
./prova2 <dll folder> <hash list>                    # processes blocks, repeatable
./prova3 <dll folder> <hash list> <profili.txt> music   # 20-band curve within 0.5 dB of the tuning
AUDIO_YOGA_DIR=<private folder> ./prova_plugin ./audio_yoga.so   # plugin with irregular block sizes
bash prove/prova_pipewire.sh <private folder>        # inside PipeWire on a dummy output, no sound
sudo bash ../../avvio/audio-yoga.sh                  # install on the running system
```

### Known limits

- The addresses in `indirizzi.h` are for DAX3 3.30812.891.0. Another build needs them found again.
- The system volume acts before the engine; in Windows it acts after. The link between volume and regulator is not reproduced.
- Headphones and Bluetooth are not processed.
- The profiles change the sound, not the maximum level: see [Is it as loud as Windows?](#is-it-as-loud-as-windows-no)
- Lesson from 2026-11-17: measure at the final output, not at the filter. The compressor of "Altoparlanti potenziati" flattened every profile to within 0.4 dB, which is why Audio Yoga has its own speaker chain.

## Display, webcam, Secure Boot, other distributions

**Display.** The panel has seven factory ICC profiles, `TPLCD_8AC2_<mode>.icm` (sRGB, DisplayP3, DCIP3, AdobeRGB, REC709, Default, Native). They are not tracked. In KDE: System Settings › Display › Colour profile. They are Windows "MHC2" profiles; whether KWin applies the factory correction stored in that tag has not been verified.

**Webcam.** Fedora's kernel has the drivers (`qcom-camss` for `qcom,x1e80100-camss`, `ov02c10`, `i2c-qcom-cci`, the camera clock controller). The device tree has none of the nodes: no `camcc`, `cci`, `camss`, sensor or camera regulators. A working description exists outside mainline in `aruhier/linux-slim7x-x1e`: sensor on `cci1` bus 1 at address `0x36`, reset on `tlmm 237`, `CAM_CC_MCLK4_CLK` at 19.2 MHz, supplies `vreg_l7b_2p8`, `vreg_l1m_1p2`, `vreg_l3m_1p8`, `csiphy4`, two data lanes. That tree uses a modified `camss` driver, so its nodes cannot be copied as they are. Wrong regulator voltages can damage the sensor. Full notes: `HANDOFF.md`, section 12.

**Secure Boot.** The factory database holds only "Microsoft Windows Production PCA 2011" and "Windows UEFI CA 2023". "Microsoft UEFI CA 2023", which signs Fedora's shim, is missing, and the BIOS cannot load certificates from a file. Windows ships the official package that adds it. Procedure and scripts: `strumenti/secureboot/LEGGIMI.txt`, `strumenti/windows/`. For now this is moot: the keyboard fix needs an unsigned kernel, so Secure Boot stays off. Check the BitLocker state before any Secure Boot change.

**Other distributions.** `strumenti/docs/ALTRE-DISTRO.md`.

## Reverse-engineering notes and tools

| Document | Subject |
|---|---|
| `strumenti/audio-auto/REVERSE-AUDIO-WINDOWS.md` | The Windows audio chain: ACDB decoding, speaker tuning, measurements (section 6), speaker protection (section 9). |
| `strumenti/audio-auto/dolby/01-architettura.md` … `10-integrazione-app.md` | Study of Dolby DAX3 on this laptop: architecture, APO interface, dependencies, service, activation, core, public prior work, running the DLL, app integration. |
| `strumenti/audio-auto/dolby/PROGETTO.md`, `PIANO-1-motore-a-file.md` | Audio Yoga design and first implementation plan. |
| `strumenti/audio-auto/windows-dolby-taratura.txt` | The Dolby tuning of this model, described. |
| `strumenti/audio/protezione/amplificatori/` | Amplifier registers: the Windows write sequence against the live values under Linux. |

| Tool | Purpose |
|---|---|
| `strumenti/tools/re-audio/acdb_*.py` | Read the Qualcomm ACDB calibration database: scan, decode, graph, speaker chain, calibration keys, speaker-protection data file. |
| `strumenti/tools/re-audio/hive_spkr.py` | Read keys from an offline Windows registry hive, for R0 and T0. |
| `strumenti/tools/re-audio/wsa_profilo.py` | Build the Windows amplifier profile and compare it with the registers under Linux. |
| `strumenti/tools/re-audio/dolby_taratura.py` | Dolby tuning XML to readable JSON, with units. |
| `strumenti/tools/misura-audio.py` | Tone steps and sweeps through the internal microphones. |
| `sorgenti/analisi/fdt_extract.py`, `dtb_diff.py`, `initrd_ls.py` | Device tree and initrd inspection. |

The notes mark each claim as **seen** (read in a file or measured), **inferred**, or unknown. Please keep that habit.

## Proprietary content

Tracked in this repository, and the reason it must stay private:

| Path | What it is |
|---|---|
| `strumenti/firmware/qcom/` | Qualcomm firmware from this laptop's Windows driver store. Three generic GPU files come from linux-firmware. |
| `strumenti/audio/windows-driver/`, `strumenti/audio/windows/` | Windows audio driver packages: Qualcomm drivers, the ACDB calibration database, voice models, and the Dolby DAX3 extension package with its tuning XML files. |
| `strumenti/audio-auto/windows-dolby-taratura.txt`, `strumenti/tools/re-audio/catena-altoparlanti-decodificata.json` | Values decoded from the files above. |
| `strumenti/log/`, `strumenti/diag-*.txt`, `strumenti/riepilogo-*.txt`, `strumenti/esito-*.txt` | Diagnostic output with hardware identifiers. |

Never tracked (see `.gitignore`): the two Dolby libraries, the decoded tuning and the engine's profile file, the Windows endpoint properties, the panel's ICC profiles, the speaker-protection data files with this unit's R0 and T0, and the firmware inside the initrd tree.

Redistributable under their own terms: the Fedora kernel with the patched device tree (`strumenti/boot/`), the Fedora packages, the LADSPA plugins, the ALSA UCM archive, Microsoft's public Secure Boot certificates.

Before a public version: remove the four rows of the table from the tree **and from the git history**, and look for user-specific paths in the scripts under `sorgenti/`.

## Safety rules

Each of these comes from something that went wrong, or nearly did.

1. **Speakers.** Do not raise `PA Volume` or the driver caps above the kit's values without working speaker protection. Raising the gain is a decision for the owner of the laptop, every time. `prova-vi-18db.sh` and `prova-protezione.sh` do raise it to the Windows level: read them before running them.
2. **DSP drivers.** With kernel 7.2.11, detaching a GPR driver removes its service port and leaves a stale callback. Never re-attach one without `gprport.ko`. Never unload the stock `snd_q6apm`: `q6prm` uses it. Do not suspend during a swap.
3. **Kernel modules** are built for exactly 7.2.11-300.fc45.aarch64. For another kernel, rebuild with `make BUILD=<dir>`.
4. **Kernel command line.** Never use `systemd.run=`.
5. **GPIO 65** resets the embedded controller. Do not touch it.
6. **USB adapters.** A JMicron `152D:0567` bridge works. An ASMedia `174C:55AA` bridge gave UAS resets.
7. **The stick is written by more than one system.** List the EFI partition and `STRUMENTI` before writing, and never overwrite a file you did not create.
8. **Webcam.** Copy regulator voltages exactly from a working tree, or risk the sensor.

## Working together

### Is your laptop the same?

Check these first, and say so if any differs:

| Item | This unit | How to read it |
|---|---|---|
| Machine type | 83ED (`Yoga Slim 7 14Q8X9`) | `cat /sys/class/dmi/id/product_name /sys/class/dmi/id/product_version` |
| BIOS | NHCN62WW | `cat /sys/class/dmi/id/bios_version` |
| Device tree model | Lenovo Yoga Slim 7x | `cat /sys/firmware/devicetree/base/model` |
| Audio subsystem | `IDEA4001` | Name of the tuning XML in the Windows `dax3_ext_qc` driver package |
| Dolby libraries | 3.30812.891.0 | `sha256sum` of the two DLLs against `strumenti/audio-auto/dolby/dati/sha256-dll-yoga.txt` |

### What a second unit can answer

- Does your keyboard need 100 kHz too, and with which BIOS version? This decides how the kernel patch should be worded.
- Your R0 values, from Windows (registry) and from Linux (`statovi.py`).
- The same speaker measurements with `tools/misura-audio.py`.
- Another build of the Dolby libraries: the function addresses for it.
- A real installation to the internal disk, which has never been done here.
- The webcam device tree.

### How to send results

- Run `sudo bash 1-DIAGNOSTICA.sh` and send the summary. Remove serial numbers and MAC addresses first.
- Work on a branch and open a pull request.
- Keep vendor files out of commits. If you need a new kind of private file, add it to `.gitignore` first.
- Write what you saw or measured, and say what is only inferred.
- Italian or English are both fine. The log files (`HANDOFF.md`, `handover.md`, `memory.md`) are updated at every checkpoint, so that the next session, human or AI-assisted, can pick up without asking.

### Getting the private files from your own laptop

| Need | How |
|---|---|
| Firmware | `8-INSTALLA-FIRMWARE.sh` with your files, or Fedora's `qcom-firmware-extract`. |
| Windows driver packages | Elevated PowerShell: `Export-WindowsDriver -Online -Destination <folder>`. |
| Dolby libraries and tuning | See [Private files](#private-files). |
| Speaker-protection data | `tools/re-audio/acdb_prot_blob.py` with the ACDB tables and your R0 and T0, read with `hive_spkr.py <SYSTEM hive> SpeakerProt`. |

## Open items

1. First cold boot with the changes of 2026-11-17 (CPU scaling, CDSP from the initramfs, Audio Yoga starting by itself).
2. Speaker protection in daily use, then amplifiers at 18 dB. See [What is missing for daily use](#what-is-missing-for-daily-use).
3. A real installation of Fedora to the internal disk.
4. Webcam device tree.
5. Sending the keyboard patch upstream.
6. Audio Yoga: headphones and Bluetooth, system volume after the engine, other library builds.
7. Secure Boot together with the keyboard fix.

## Glossary

| Italian | English |
|---|---|
| `LEGGIMI` | README |
| `strumenti` | tools (the kit) |
| `chiavetta` | USB stick |
| `avvio` | boot, start-up |
| `sorgenti` | sources |
| `vecchi` | old, superseded |
| `tastiera` | keyboard |
| `schermo` | display |
| `altoparlanti`, `amplificatori` | speakers, amplifiers |
| `protezione` | protection |
| `taratura` | tuning, calibration data |
| `prova`, `prove` | test, tests |
| `esito`, `riepilogo` | result, summary |
| `scambia` | swap |
| `pacchetti` | packages |
| `impronte` | hashes |
| `guadagno`, `tetto` | gain, cap |
| `incrocio` | crossover |
| `spinta` | boost ("maximum volume") |
| `dialoghi`, `livellatore` | dialogue enhancement, volume leveller |
| `profili`: `Dinamico`, `Film`, `Musica`, `Gioco`, `Voce`, `Spento` | profiles: Dynamic, Movie, Music, Game, Voice, Off |
| `visto`, `dedotto` | seen, inferred |

## Credits and licences

- **geocausa/SP11X1e-audio** (BSD-2-Clause): speaker protection and Dolby on the Surface Pro 11. The DLL loader in `strumenti/audio/dolby/pe.c` derives from its `sp11_vlldp_pe_loader.h`, and the amplifier profile from its Windows driver trace. Read its documents before repeating a step.
- **aruhier/linux-slim7x-x1e**: the working reference for the webcam.
- **Fedora**: the kernel, the Snapdragon laptop install guide, `qcom-firmware-extract`.
- **swh-plugins** (GPL): the LADSPA compressor and limiter. Licence text in `strumenti/audio-auto/ladspa/`.

No licence has been chosen yet for the original scripts and code in this repository. Third-party parts keep their own licences.

Dolby and Dolby Atmos are trademarks of Dolby Laboratories. Qualcomm, Lenovo and Microsoft names are trademarks of their owners. This project is not affiliated with or endorsed by any of them.
