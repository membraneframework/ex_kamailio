#!/usr/bin/env bash
# Generate a PCMA RTP PCAP for SIPp's play_pcap_audio AND a matching plain
# PCMA file for direct playback. The pcap is what the UAC streams into the
# relay; the .alaw is the same audio in a form you can ffplay alongside
# the sink's capture to confirm by ear that the relay carried the audio
# through intact.
#
# Each frequency in the freq list plays for 1 second; total duration =
# (number of frequencies) seconds, at 50 packets/sec (20 ms PCMA frames).
#
# Usage:
#   gen_tone_pcap.sh OUT.pcap OUT.alaw FREQ1,FREQ2,...,FREQN
#
# Example (a ten-second up-and-down melody):
#   gen_tone_pcap.sh tone.pcap tone.alaw \
#     220,330,440,550,660,880,660,550,440,330
#
# Listen back to the reference with:
#   ffplay -f alaw -ar 8000 -ac 1 OUT.alaw

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: $0 OUT.pcap OUT.alaw FREQ1,FREQ2,..." >&2
  exit 2
fi

out_pcap="$1"
out_alaw="$2"
IFS=',' read -ra freqs <<< "$3"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Synthesize each 1-second segment as raw PCMA, then concatenate. PCMA is
# bytewise-concatenatable because it's a fixed-rate codec with no framing.
seg_files=()
for i in "${!freqs[@]}"; do
  f="${freqs[$i]}"
  seg="$tmpdir/seg_$(printf '%04d' "$i").alaw"
  ffmpeg -nostdin -loglevel error -y \
    -f lavfi -i "sine=frequency=${f}:duration=1" \
    -ar 8000 -ac 1 -f alaw "$seg"
  seg_files+=("$seg")
done

cat "${seg_files[@]}" > "$out_alaw"
echo "wrote reference $(stat -f%z "$out_alaw" 2>/dev/null || stat -c%s "$out_alaw") bytes to $out_alaw"

python3 - "$out_alaw" "$out_pcap" <<'PY'
import struct, sys

in_path, out_path = sys.argv[1], sys.argv[2]
with open(in_path, "rb") as f:
    data = f.read()

# pcap global header (LINKTYPE_ETHERNET = 1; SIPp's play_pcap_audio rejects
# LINKTYPE_NULL even though libpcap handles it transparently)
header = struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1)

frame = 160          # 20 ms @ 8 kHz PCMA
ssrc = 0xCAFEBABE
rtp_seq = 0
rtp_ts = 0
pcap_us = 0

with open(out_path, "wb") as out:
    out.write(header)
    n = 0
    for i in range(0, len(data), frame):
        chunk = data[i:i + frame]
        if len(chunk) < frame:
            chunk += b"\xd5" * (frame - len(chunk))   # PCMA "silence" byte
        rtp = struct.pack(">BBHII", 0x80, 0x08, rtp_seq, rtp_ts, ssrc) + chunk
        udp = struct.pack(">HHHH", 5004, 5004, 8 + len(rtp), 0)
        ip = struct.pack(
            "!BBHHHBBH4s4s",
            0x45, 0x00, 20 + 8 + len(rtp),
            0x0000, 0x4000,
            64, 17, 0x0000,
            b"\x7f\x00\x00\x01", b"\x7f\x00\x00\x01",
        )
        eth = b"\x00\x00\x00\x00\x00\x02" + b"\x00\x00\x00\x00\x00\x01" + b"\x08\x00"
        pkt = eth + ip + udp + rtp
        sec, usec = divmod(pcap_us, 1_000_000)
        out.write(struct.pack("<IIII", sec, usec, len(pkt), len(pkt)))
        out.write(pkt)
        rtp_seq = (rtp_seq + 1) & 0xFFFF
        rtp_ts = (rtp_ts + frame) & 0xFFFFFFFF
        pcap_us += 20_000
        n += 1

print(f"wrote {n} packets ({n * 20} ms) to {out_path}")
PY
