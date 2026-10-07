#!/bin/sh
# Places one call through the stack and checks that the audio went through
# the relay in both directions: the UAC plays g711a.pcap, the UAS echoes it.
set -eu
cd "$(dirname "$0")"

rm -f recordings/*.raw
docker compose up -d --build --wait --force-recreate
docker compose run --build --rm sipp-uac > /dev/null

expected=56640 # PCMA bytes in SIPp's g711a.pcap: 236 packets of 240
for f in recordings/*.raw; do
  size=$(wc -c < "$f")
  test "$size" -eq $expected || { echo "FAIL: $f has $size bytes, expected $expected"; exit 1; }
done
cmp recordings/*__offerer_to_answerer.raw recordings/*__answerer_to_offerer.raw
echo "OK: $expected bytes relayed each way"
