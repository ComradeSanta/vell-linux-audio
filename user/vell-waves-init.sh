#!/usr/bin/bash
# vell-waves-init.sh — push the ChromeOS Waves speaker tuning blob into the
# SOF codec-adapter control (vell topology). Safe: if this fails, audio still
# plays with topology defaults. Re-run after suspend/resume if needed.
BLOB=/opt/waves/vell/waves_params_speaker.bin
CTL="CODEC_ADAPTER1.0 Waves Speakers Setup 1"
ACTL="$HOME/.local/bin/actl"

for i in $(seq 1 30); do
    $ACTL tlv "$CTL" "$BLOB" >/dev/null 2>&1 && { echo "waves tuning applied"; exit 0; }
    sleep 1
done
echo "waves control not reachable (card down?); audio may still play" >&2
exit 1
