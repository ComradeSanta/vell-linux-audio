# blobs/ provenance

All files extracted from the official ChromeOS recovery image
`chromeos_16805.36.0_brya_recovery_stable-channel_BryaMPKeys-v23.bin`
(chromeos_16805.36.0, October 2026 stable), paths as shipped in the image's
ROOT-A partition:

| Repo path | Image path | What it is |
|---|---|---|
| `cirrus/cs35l41-dsp1-spk-{prot,cali}-103c8c08-{tl,tr,wl,wr}.{wmfw,bin}` | `/lib/firmware/cirrus/` | Cirrus CS35L41 amp DSP firmware, HP subsystem 103C8C08, per speaker position (tl/tr = tweeters, wl/wr = woofers). `prot` = speaker protection (used, fw preset 9); `cali` = calibration variant (unused, kept for reference). wmfw contains the "HP Vell Ripple" tuning. |
| `sof/taeko/sof-adl.{ri,ldc}` | `/lib/firmware/intel/sof/taeko/` | SOF DSP firmware for Alder Lake as ChromeOS ships it for this board family (vell ships symlinks to the taeko build). |
| `sof-tplg/sof-adl-cs35l41.tplg` | `/lib/firmware/intel/sof-tplg/vell/` | **Board-specific** topology (Waves CODEC_ADAPTER pipeline). Do not substitute the root-level `/lib/firmware/intel/sof-tplg/sof-adl-cs35l41.tplg` — its MULTIBAND_DRC widgets are rejected by this firmware and the card fails to probe. |
| `waves/waves_params_speaker.bin` | `/opt/waves/vell/` | Waves speaker tuning parameters, pre-framed as a SOF TLV blob ({numid=3 SOF_CTRL_CMD_BINARY, length, sof_abi_hdr, data}). Push raw into control `CODEC_ADAPTER1.0 Waves Speakers Setup 1`. |
| `ucm/sof-ssp_amp.vell/` | `/usr/share/alsa/ucm/` | ChromeOS UCM — the source of the amp cset sequence (gain 17, FW 9, routing). Reference; not installed by install.sh. |
| `cras/vell/` | `/etc/cras/vell/` | ChromeOS CRAS config (volume curve, DSP chain). Reference. |
