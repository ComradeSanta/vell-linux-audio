#!/usr/bin/bash
# extract-from-recovery.sh — pull the audio tuning (SOF fw, topology, CS35L41
# amp firmware, Waves blobs, UCM, CRAS configs) out of an official ChromeOS
# recovery image, for people who prefer to extract blobs themselves or who
# have a different board than the pre-built ones in blobs/.
#
# Usage:  ./extract-from-recovery.sh [HWID-prefix] [output-dir]
#         default HWID prefix: VELL  (HP Dragonfly Pro Chromebook)
#         e.g. ./extract-from-recovery.sh REDRIX
#
# Requirements: curl, python3, e2fsprogs (debugfs). ~8 GB free disk space.
# No root needed. Big downloads are cleaned up automatically.
set -euo pipefail
HWID="${1:-VELL}"
OUT="${2:-./extracted}"
WORK=$(mktemp -d /tmp/cros-audio-extract.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

command -v curl >/dev/null || { echo "need curl"; exit 1; }
command -v python3 >/dev/null || { echo "need python3"; exit 1; }
command -v debugfs >/dev/null || { echo "need e2fsprogs (debugfs)"; exit 1; }

echo "== finding newest stable recovery image for HWID $HWID"
curl -s --retry 3 -o "$WORK/recovery.json" \
    "https://dl.google.com/dl/edgedl/chromeos/recovery/recovery.json"
IMG=$(python3 - "$WORK/recovery.json" "$HWID" <<'EOF'
import json, sys, re
d = json.load(open(sys.argv[1]))
if isinstance(d, dict): d = d.get('list', [])
hwid = sys.argv[2]
for e in d:
    if e.get('channel') == 'stable' and re.match(rf'^{hwid}-', e.get('hwidmatch', '')):
        print(e['file']); break
EOF
)
[ -n "$IMG" ] || { echo "no stable recovery image found for HWID $HWID"; exit 1; }
URL="https://dl.google.com/dl/edgedl/chromeos/recovery/$IMG"
echo "   $URL"

echo "== downloading (a few GB)"
curl -sL --retry 3 -o "$WORK/img.bin.zip" "$URL"
python3 - "$WORK/img.bin.zip" "$WORK" <<'EOF'
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
EOF
BIN=$(find "$WORK" -maxdepth 1 -name '*.bin' ! -name '*.bin.zip' | head -1)
[ -n "$BIN" ] || { echo "image extraction failed"; exit 1; }

echo "== carving ROOT-A"
python3 - "$BIN" "$WORK" <<'EOF'
import sys, struct
f = open(sys.argv[1], 'rb')
f.seek(512)
sig, rev, hsz, crc, _, cur, bak, first, last, guid, pe_lba, npart, psz, pcrc = \
    struct.unpack('<8sIIIIQQQQ16sQIII', hdr := f.read(92))
assert sig == b'EFI PART', 'not a GPT image'
f.seek(pe_lba * 512)
for _ in range(npart):
    e = f.read(psz)
    name = e[56:128].decode('utf-16-le').rstrip('\x00')
    if name == 'ROOT-A':
        l0, l1 = struct.unpack('<QQ', e[16:32])
        bs, cnt = l0 * 512, (l1 - l0 + 1) * 512
        break
else:
    sys.exit('ROOT-A not found')
f.close()
with open(sys.argv[1], 'rb') as src, open(sys.argv[2] + '/roota.ext4', 'wb') as dst:
    src.seek(bs); remaining = cnt
    while remaining:
        chunk = src.read(min(1 << 24, remaining))
        if not chunk: break
        dst.write(chunk); remaining -= len(chunk)
EOF

echo "== extracting audio trees"
mkdir -p "$OUT"/{cirrus,sof,sof-tplg,waves,ucm,cras}
ROOTA="$WORK/roota.ext4"
mkdir -p "$WORK/o/cirrus" "$WORK/o/sof" "$WORK/o/sof-tplg" "$WORK/o/waves" "$WORK/o/ucm" "$WORK/o/cras"
# board is inferred from the HWID prefix: ChromeOS uses lowercase board names
# in /opt/waves and board-specific subdirs; try the prefix itself first.
BOARD=$(echo "$HWID" | tr 'A-Z' 'a-z')
for pair in "etc/cras:cras" "usr/share/alsa/ucm:ucm" "lib/firmware/cirrus:cirrus" \
            "lib/firmware/intel/sof:sof" "lib/firmware/intel/sof-tplg:sof-tplg" "opt/waves:waves"; do
    src="${pair%%:*}"; dst="${pair##*:}"
    debugfs -R "rdump /$src $WORK/o/$dst" "$ROOTA" 2>/dev/null || true
done
# keep only what relates to this board / the platform
cp -a "$WORK/o/cirrus/cirrus"/* "$OUT/cirrus/" 2>/dev/null || true
BOARD_SOF=$(find "$WORK/o/sof/sof" -maxdepth 1 -type d -name "$BOARD" 2>/dev/null | head -1)
if [ -n "$BOARD_SOF" ]; then cp -aL "$BOARD_SOF"/. "$OUT/sof/"; else cp -a "$WORK/o/sof/sof"/* "$OUT/sof/" 2>/dev/null || true; fi
BOARD_TPLG=$(find "$WORK/o/sof-tplg/sof-tplg" -maxdepth 1 -type d -name "$BOARD" 2>/dev/null | head -1)
if [ -n "$BOARD_TPLG" ]; then cp -aL "$BOARD_TPLG"/. "$OUT/sof-tplg/";
else for f in "$WORK/o/sof-tplg/sof-tplg/"*.tplg; do cp -a "$f" "$OUT/sof-tplg/" 2>/dev/null || true; done; fi
BOARD_WAVES=$(find "$WORK/o/waves/waves" -maxdepth 1 -type d -name "$BOARD" 2>/dev/null | head -1)
[ -n "$BOARD_WAVES" ] && cp -aL "$BOARD_WAVES"/. "$OUT/waves/" 2>/dev/null || true
BOARD_UCM=$(find "$WORK/o/ucm/ucm" -maxdepth 1 -type d -iname "*$BOARD*" 2>/dev/null | head -1)
[ -n "$BOARD_UCM" ] && cp -a "$BOARD_UCM" "$OUT/ucm/" 2>/dev/null || true
BOARD_CRAS=$(find "$WORK/o/cras/cras" -maxdepth 1 -type d -name "$BOARD" 2>/dev/null | head -1)
[ -n "$BOARD_CRAS" ] && cp -a "$BOARD_CRAS" "$OUT/cras-board/" 2>/dev/null || true

echo
echo "Extracted to $OUT (firmware in cirrus/ + sof/, board topology in sof-tplg/,"
echo "waves + ucm + cras-board if found). Inspect with: find $OUT -type f | less"
echo "NOTE: layout may differ slightly from this repo's blobs/; adapt paths."
