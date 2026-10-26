# vell-linux-audio

Full ChromeOS speaker quality for the **HP Dragonfly Pro Chromebook** (board
**"vell"**) running Arch Linux (or a derivative) with PipeWire/WirePlumber +
SOF. On a fresh Arch install the speakers sound thin, harsh and quiet — this
restores exactly what ChromeOS played, because it installs the same tuning
ChromeOS uses, in the same places ChromeOS puts it.

Works around / fixes (all three layers of the problem):

| Layer | Stock Arch | This repo |
|---|---|---|
| Amp DSP (4× Cirrus CS35L41: TL/TR tweeters, WL/WR woofers) | raw passthrough, no crossover/protection/EQ | each amp loads its own HP **"Vell Ripple"** speaker-protection tuning, routed through the DSP at ChromeOS gain |
| SOF DSP (Intel ADL) | stock `sof-adl-cs35l41.tplg` is a dumb pipe | ChromeOS SOF firmware + **vell-specific topology** with the Waves speaker-processing pipeline; Waves tuning blob pushed into it |
| Session (PipeWire/WirePlumber) | adaptive clock, device suspends between songs | 48 kHz lock + high-quality resampling; device kept open (the amp power-up handshake is flaky — one failed attempt per stream otherwise) |

Verified on: Arch (zen kernel 7.2), sof-firmware 2026.09, PipeWire 1.6.
The mechanism (per-amp firmware suffixes, wm_adsp) is mainline, so stock
`linux` should behave the same; report if not.

## Quick start

```bash
git clone https://github.com/<you>/vell-linux-audio.git
cd vell-linux-audio
sudo ./install.sh
reboot
```

Then just play music. The user services re-apply the amp routing and Waves
tuning at every login.

Requirements: `gcc`, `alsa-lib` (headers, for the `actl` helper),
`pipewire`, `wireplumber`, `sof-firmware`. The installer checks and tells you
if something's missing.

## After install

Verify:

```bash
journalctl -b -k | grep 'Vell Ripple'      # per-amp tuning loaded (4 lines)
~/.local/bin/actl get 'TL PCM Source'      # enum = 1  (amps route through DSP)
journalctl --user -u vell-waves-init       # waves tuning applied
```

Known good-to-know:

- **Suspend/resume**: the DSP layers can drop their tuning on resume. If
  sound regresses (flat/harsh), run
  `~/.local/bin/vell-amp-init.sh && ~/.local/bin/vell-waves-init.sh`.
- **linux-firmware upgrades overwrite** the SOF firmware/topology. If quality
  regresses after a firmware update, re-run `sudo ./install.sh`.
- **Volume**: full-scale is loud; the Waves + protection stack assumes the
  ChromeOS amp gain (17/20) which the installer sets.

## Rollback / troubleshooting

```bash
sudo ./restore.sh   # everything back to stock Arch audio, then reboot
```

If the card ever comes up as "Dummy Output" (topology rejected), the escape
hatch is `sudo ./restore.sh && reboot` from a TTY (Ctrl+Alt+F3). Diagnostics:
`journalctl -b -k | grep -iE 'sof|cs35l41|topology'`.

`~/.local/bin/vell-amp-raw.sh` reverts just the amps to the raw (untuned but
audible) route.

## What's in the box

```
install.sh                  root installer (fw + topology + blobs + user session)
restore.sh                  full rollback
extract-from-recovery.sh    pull tuning from any ChromeOS recovery image
user/                       session parts: PipeWire 48k lock, WirePlumber keep-open,
                            actl.c (ALSA control helper), vell-amp-init / vell-waves-init
                            services + scripts, vell-amp-raw fallback
blobs/cirrus/               CS35L41 per-speaker fw, HP subsystem 103C8C08
                            (spk-prot = protection/limits; spk-cali = calibration variant)
blobs/sof/taeko/            ChromeOS SOF DSP firmware (sof-adl.ri/.ldc)
blobs/sof-tplg/             vell topology: Waves CODEC_ADAPTER pipeline
blobs/waves/                Waves speaker tuning params (TLV-framed)
blobs/ucm/, blobs/cras/     ChromeOS UCM + CRAS configs for reference
```

## How it works (the short version)

The speakers are four CS35L41 "smart amps" with an on-chip DSP, driven by the
Intel SOF DSP. ChromeOS tunes **both** DSPs; stock Linux tunes neither — the
amps pass full-range audio straight into tweeters/woofers and the SOF
topology is a plain pipe. This repo:

1. Installs ChromeOS's SOF firmware + the board-specific topology (which
   contains the Waves CODEC_ADAPTER control). The generic topology crashes
   this card — only the `vell/` one matches the firmware build.
2. Pushes the Waves parameters blob into that control at login (raw TLV —
   the blob ships pre-framed as `{numid=3 SOF_CTRL_CMD_BINARY, len, SOF ABI header}`).
3. Routes each amp through its own DSP (`DSP1 Firmware=9` speaker-protection
   preset, `PCM Source=1`, gain 17/20 — exactly the ChromeOS UCM sequence).
   The kernel then requests `cirrus/cs35l41-dsp1-spk-prot-<subsystem>-<pos>.wmfw`
   per amp (lowercase subsystem + `-tl/-tr/-wl/-wr`), which step 2 of the
   installer provides. Without those files the kernel falls back to a generic
   Cirrus preset whose algorithm is **silent** on this wiring — that trap cost
   us two debugging rounds, so it's documented here.

## Other boards

The blobs here are vell-specific (HP subsystem `103C8C08`, hwid
`VELL-SVGZ`). For a different Chromebook, `./extract-from-recovery.sh
<HWID-prefix>` pulls the same categories of tuning out of that board's own
recovery image — the mechanism is identical on any SOF + CS35L41 machine,
but the cset sequences and firmware names may differ; read your board's UCM
in the extraction output and adapt.

## Provenance & license

- Code in this repo: MIT (see `LICENSE`).
- Files in `blobs/` are extracted from the official ChromeOS recovery image
  `chromeos_16805.36.0_brya_recovery_stable-channel` (vell = `VELL-SVGZ`) for
  interoperability with the hardware they shipped on. They remain the
  property of their owners (Google / HP / Cirrus Logic / Waves / Intel).
- Method independently discovered via the ChromeOS recovery image; community
  context: [chrultrabook docs](https://docs.chrultrabook.com) and
  [WeirdTreeThing/chromebook-linux-audio](https://github.com/WeirdTreeThing/chromebook-linux-audio)
  (which takes a different approach — UCM-based — and is worth trying first
  on other boards).
