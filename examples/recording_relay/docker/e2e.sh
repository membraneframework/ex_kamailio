#!/bin/sh
# Places one call through the stack and checks that the audio went through
# the relay in both directions: the UAC plays g711a.pcap, the UAS echoes it.
set -eu
cd "$(dirname "$0")"

call="recordings/1-1@127.0.0.1" # SIPp's Call-ID is <call>-<pid>@<ip>, and sipp is PID 1 in its container
rm -f "$call"__*.raw
export ADVERTISE_IP=127.0.0.1 # overrides a .env left over from a phone demo
docker compose up -d --build --wait relay kamailio sipp-uas
docker compose run --rm sipp-uac > /dev/null

expected=56640 # PCMA bytes in SIPp's g711a.pcap: 236 packets of 240
for f in "$call"__offerer_to_answerer.raw "$call"__answerer_to_offerer.raw; do
  size=$(wc -c < "$f")
  test "$size" -eq $expected || { echo "FAIL: $f has $size bytes, expected $expected"; exit 1; }
done
cmp "$call"__offerer_to_answerer.raw "$call"__answerer_to_offerer.raw
echo "OK: $expected bytes relayed each way"
