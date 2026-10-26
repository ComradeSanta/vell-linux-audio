#!/usr/bin/bash
# install.sh — restore full ChromeOS speaker quality on the HP Dragonfly Pro
# Chromebook (board "vell") running Arch Linux (or derivative) with
# PipeWire/WirePlumber + SOF.
#
# What it does:
#   1. Installs the ChromeOS SOF firmware (taeko build) and the vell-specific
#      topology (Waves CODEC_ADAPTER pipeline) with backups of the originals.
#   2. Installs the per-speaker CS35L41 amp firmware ("HP Vell Ripple"
#      protection tuning) under the names the kernel requests.
#   3. Installs the Waves speaker tuning blob to /opt/waves/vell/.
#   4. Sets up the user session parts: 48 kHz PipeWire lock, keep-open,
#      vell-amp-init + vell-waves-init services.
#
# Idempotent. Run again after linux-firmware package upgrades (they overwrite
# the SOF firmware). Reboot once after installing.
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

if [ $EUID -ne 0 ]; then echo "run with sudo" >&2; exit 1; fi
REAL_USER="${SUDO_USER:-}"
[ -n "$REAL_USER" ] || { echo "run via sudo from your user account" >&2; exit 1; }
REAL_UID=$(id -u "$REAL_USER")
UHOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

FW=/usr/lib/firmware
card_ok() {
    [ -d /sys/class/dmi/id ] || return 1
    grep -qi vell /sys/class/dmi/id/board_name 2>/dev/null && return 0
    return 1
}
if ! card_ok && [ $FORCE -ne 1 ]; then
    echo "This machine does not identify as vell (board_name: $(cat /sys/class/dmi/id/board_name 2>/dev/null))."
    echo "The blobs here are tuned for exactly that board. Use --force to install anyway."
    exit 1
fi

echo "== 1/4 ChromeOS SOF firmware + vell topology"
# NOTE: community/sof-adl.ri and sof/sof-adl.{ri,ldc} are SYMLINKS on Arch
# (-> sof-tgl.ri / intel-signed/...). Back up, remove, then install real
# files — never write through a symlink.
for rel in community/sof-adl.ri community/sof-adl.ldc sof-adl.ri sof-adl.ldc; do
    dst="$FW/intel/sof/$rel"
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        [ -e "$dst.arch-orig" ] || [ -L "$dst.arch-orig" ] || cp -a "$dst" "$dst.arch-orig"
        rm -f "$dst"
    fi
    install -m 0644 "$REPO/blobs/sof/taeko/$(basename "$rel")" "$dst"
    echo "  $dst"
done
t="$FW/intel/sof-tplg/sof-adl-cs35l41.tplg"
[ -e "$t.arch-orig" ] || cp -a "$t" "$t.arch-orig"
install -m 0644 "$REPO/blobs/sof-tplg/sof-adl-cs35l41.tplg" "$t"
echo "  $t (vell Waves topology)"

echo "== 2/4 per-speaker CS35L41 amp firmware"
for pos in tl tr wl wr; do
    for name in "103c8c08-$pos" "103C8C08-$pos"; do
        install -m 0644 "$REPO/blobs/cirrus/cs35l41-dsp1-spk-prot-103c8c08-$pos.wmfw" "$FW/cirrus/cs35l41-dsp1-spk-prot-$name.wmfw"
        install -m 0644 "$REPO/blobs/cirrus/cs35l41-dsp1-spk-prot-103c8c08-$pos.bin"  "$FW/cirrus/cs35l41-dsp1-spk-prot-$name.bin"
    done
done
# subsystem-only fallback (no per-amp suffix known): use the TWEETER tuning —
# its limits are the tight ones, so every speaker stays protected (may
# slightly over-protect woofers until a suffix-aware kernel loads per-amp files)
for name in 103c8c08 103C8C08; do
    install -m 0644 "$REPO/blobs/cirrus/cs35l41-dsp1-spk-prot-103c8c08-tl.wmfw" "$FW/cirrus/cs35l41-dsp1-spk-prot-$name.wmfw"
    install -m 0644 "$REPO/blobs/cirrus/cs35l41-dsp1-spk-prot-103c8c08-tl.bin"  "$FW/cirrus/cs35l41-dsp1-spk-prot-$name.bin"
done
echo "  installed to $FW/cirrus/"

echo "== 3/4 Waves tuning blob"
install -d /opt/waves/vell
install -m 0644 "$REPO/blobs/waves/waves_params_speaker.bin" /opt/waves/vell/
echo "  /opt/waves/vell/waves_params_speaker.bin"

echo "== 4/4 user session ($REAL_USER)"
UBIN="$UHOME/.local/bin"
UCFG="$UHOME/.config"
install -d "$UBIN" "$UCFG/pipewire/pipewire.conf.d" "$UCFG/wireplumber/wireplumber.conf.d" "$UCFG/systemd/user"
install -m 0644 "$REPO/user/20-sof-clock.conf"      "$UCFG/pipewire/pipewire.conf.d/"
install -m 0644 "$REPO/user/51-sof-keep-open.conf"  "$UCFG/wireplumber/wireplumber.conf.d/"
install -m 0755 "$REPO/user/vell-amp-init.sh"   "$UBIN/"
install -m 0755 "$REPO/user/vell-waves-init.sh" "$UBIN/"
install -m 0755 "$REPO/user/vell-amp-raw.sh"    "$UBIN/"
install -m 0644 "$REPO/user/vell-amp-init.service"   "$UCFG/systemd/user/"
install -m 0644 "$REPO/user/vell-waves-init.service" "$UCFG/systemd/user/"
if command -v gcc >/dev/null && [ -f /usr/include/alsa/asoundlib.h ]; then
    gcc -O2 -o "$UBIN/actl" "$REPO/user/actl.c" -lasound
    echo "  built $UBIN/actl"
else
    echo "  WARNING: gcc or alsa-lib headers missing; cannot build 'actl'." >&2
    echo "  Install gcc and alsa-lib, then re-run this script." >&2
    exit 1
fi
chown -R "$REAL_USER:" "$UBIN" "$UCFG/pipewire" "$UCFG/wireplumber" "$UCFG/systemd/user" 2>/dev/null || true

as_user() {
    sudo -u "$REAL_USER" env XDG_RUNTIME_DIR="/run/user/$REAL_UID" "$@"
}
as_user systemctl --user daemon-reload
as_user systemctl --user enable --now vell-amp-init.service vell-waves-init.service
# pick up the 48k + keep-open configs without waiting for next login
as_user systemctl --user restart wireplumber.service pipewire.service

echo
echo "Done. REBOOT now (the SOF card must re-probe with the new firmware)."
echo "After reboot, verify:"
echo "  journalctl -b -k | grep 'Vell Ripple'     # per-amp tuning loaded"
echo "  ~/.local/bin/actl get 'TL PCM Source'     # enum = 1"
echo "  journalctl --user -u vell-waves-init      # waves tuning applied"
echo "Then just play music. After suspend/resume, if quality regresses:"
echo "  ~/.local/bin/vell-amp-init.sh && ~/.local/bin/vell-waves-init.sh"
