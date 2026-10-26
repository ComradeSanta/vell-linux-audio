#!/usr/bin/bash
# restore.sh — undo everything install.sh did: back to stock Arch audio
# (raw untuned amps, stock SOF firmware/topology). Use if anything breaks.
set -euo pipefail

if [ $EUID -ne 0 ]; then echo "run with sudo" >&2; exit 1; fi
REAL_USER="${SUDO_USER:-}"
FW=/usr/lib/firmware

echo "== firmware/topology"
for rel in community/sof-adl.ri community/sof-adl.ldc sof-adl.ri sof-adl.ldc; do
    dst="$FW/intel/sof/$rel"
    if [ -e "$dst.arch-orig" ] || [ -L "$dst.arch-orig" ]; then
        rm -f "$dst"; mv "$dst.arch-orig" "$dst"; echo "  restored $dst"
    fi
done
t="$FW/intel/sof-tplg/sof-adl-cs35l41.tplg"
if [ -e "$t.arch-orig" ]; then mv "$t.arch-orig" "$t"; echo "  restored $t"; fi

echo "== per-amp cirrus firmware (installed by us, not in stock linux-firmware)"
for name in 103c8c08-tl 103c8c08-tr 103c8c08-wl 103c8c08-wr \
            103C8C08-tl 103C8C08-tr 103C8C08-wl 103C8C08-wr \
            103c8c08 103C8C08; do
    rm -f "$FW/cirrus/cs35l41-dsp1-spk-prot-$name.wmfw" "$FW/cirrus/cs35l41-dsp1-spk-prot-$name.bin"
done
echo "  removed from $FW/cirrus/"

echo "== waves blob"
rm -rf /opt/waves/vell

if [ -n "$REAL_USER" ]; then
    echo "== user session ($REAL_USER)"
    REAL_UID=$(id -u "$REAL_USER"); UHOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
    sudo -u "$REAL_USER" env XDG_RUNTIME_DIR="/run/user/$REAL_UID" \
        systemctl --user disable --now vell-amp-init.service vell-waves-init.service 2>/dev/null || true
    rm -f "$UHOME/.config/systemd/user/vell-amp-init.service" \
          "$UHOME/.config/systemd/user/vell-waves-init.service" \
          "$UHOME/.config/pipewire/pipewire.conf.d/20-sof-clock.conf" \
          "$UHOME/.config/wireplumber/wireplumber.conf.d/51-sof-keep-open.conf" \
          "$UHOME/.local/bin/vell-amp-init.sh" "$UHOME/.local/bin/vell-waves-init.sh" \
          "$UHOME/.local/bin/vell-amp-raw.sh" "$UHOME/.local/bin/actl"
    sudo -u "$REAL_USER" env XDG_RUNTIME_DIR="/run/user/$REAL_UID" systemctl --user daemon-reload || true
fi

echo
echo "Restored. REBOOT to load the stock firmware/topology."
