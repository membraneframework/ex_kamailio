#!/usr/bin/env bash
# Generate a PCMA RTP PCAP for SIPp's play_pcap_audio. The resulting file is
# a series of 20 ms RTP packets (50 pps) carrying a sine tone, so the relay
# receives a known, audible test signal that can be cross-checked against
# what we record on the other leg.
#
# Usage: gen_tone_pcap.sh [output.pcap] [frequency_hz] [duration_seconds]

set -euo pipefail

out="${1:-tone.pcap}"
freq="${2:-440}"
duration="${3:-3}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

ffmpeg -nostdin -loglevel error -y \
  -f lavfi -i "sine=frequency=${freq}:duration=${duration}" \
  -ar 8000 -ac 1 -f alaw \
  "$tmpdir/tone.alaw"

python3 - "$tmpdir/tone.alaw" "$out" <<'PY'
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
