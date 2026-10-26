#!/usr/bin/bash
# vell-amp-init.sh — route all four CS35L41 amps through their DSPs, which
# load the per-speaker ChromeOS tuning (HP Vell Ripple protection presets,
# installed by ~/cros-recovery/install-amp-fw.sh). Sequence mirrors the
# ChromeOS UCM (sof-ssp_amp.vell). Safe: vell-amp-raw.sh reverts if ever
# needed. Re-run after suspend/resume if quality regresses.
ACTL="$HOME/.local/bin/actl"

for i in $(seq 1 30); do
    [ -n "$($ACTL get 'TL DSP1 Firmware' 2>/dev/null | grep enum)" ] && break
    sleep 1
done

rc=0
for amp in TL WL TR WR; do
    $ACTL set "$amp DSP1 Firmware" 9        >/dev/null 2>&1 || rc=1
    $ACTL set "$amp PCM Source" 1           >/dev/null 2>&1 || rc=1
    $ACTL set "$amp DSP RX1 Source" 1       >/dev/null 2>&1 || rc=1
    $ACTL set "$amp DSP RX2 Source" 1       >/dev/null 2>&1 || rc=1
    $ACTL set "$amp DSP1 Preload Switch" 1  >/dev/null 2>&1 || rc=1
    $ACTL set "$amp Analog PCM Volume" 17   >/dev/null 2>&1 || rc=1
done
exit $rc
