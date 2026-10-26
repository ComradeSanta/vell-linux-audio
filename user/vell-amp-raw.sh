#!/usr/bin/bash
# vell-amp-raw.sh — emergency helper: force all four CS35L41 amps back to the
# raw ASP-bypass configuration (the always-audible baseline). Run this if the
# speakers ever go silent after amp-control experiments.
ACTL="$HOME/.local/bin/actl"
for amp in TL WL TR WR; do
    $ACTL set "$amp PCM Source" 0        >/dev/null
    $ACTL set "$amp DSP RX1 Source" 0    >/dev/null
    $ACTL set "$amp DSP RX2 Source" 0    >/dev/null
    $ACTL set "$amp DSP1 Preload Switch" 0 >/dev/null
    $ACTL set "$amp Analog PCM Volume" 0 >/dev/null
    $ACTL set "$amp DSP1 Firmware" 0     >/dev/null
done
echo "amps reset to raw ASP route (audible baseline)"
