#!/usr/bin/env bash
#
# Bring up the Kamailio + relay stack reachable over Tailscale, so a real
# softphone on any network (your phone on Wi-Fi or cellular, behind NAT,
# anywhere on your tailnet) can REGISTER and place calls through it.
#
# This is the reproducible "call from a real phone" path: the steps are the
# same on macOS, Linux and Windows and don't depend on the local router.
#
# Prereq: a Tailscale auth key (https://login.tailscale.com/admin/settings/keys),
# exported as TS_AUTHKEY. An ephemeral, pre-authorized key is recommended.
#
#   export TS_AUTHKEY=tskey-...
#   ./tailscale-lan.sh
#
# Then install the Tailscale app on the phone, sign into the SAME tailnet,
# and point the softphone at the sip: URI this script prints.
#
# Tear down:  docker compose -f compose.yml -f compose.lan.yml -f compose.tailscale.yml down
# (the resolved ADVERTISE_IP is written to .env, so that command — and any
#  other docker compose command in this dir — works without re-exporting it.)

set -euo pipefail
cd "$(dirname "$0")"

: "${TS_AUTHKEY:?generate an auth key at https://login.tailscale.com/admin/settings/keys, then: export TS_AUTHKEY=tskey-...}"

# Bring the sidecar up with ONLY the tailscale overlay. The full file set
# can't be parsed yet: compose would try to interpolate ADVERTISE_IP (a
# required var on kamailio/relay) before this sidecar has produced it.
TS_FILES="-f compose.tailscale.yml"
ALL_FILES="-f compose.yml -f compose.lan.yml -f compose.tailscale.yml"

echo "[tailscale-lan] starting tailscale sidecar..."
docker compose $TS_FILES up -d tailscale

echo "[tailscale-lan] waiting for a tailnet IPv4 (auth can take a few seconds)..."
ADVERTISE_IP=""
for _ in $(seq 1 60); do
  # `|| true` keeps a failed probe (tailscaled not authed yet) from tripping
  # `set -e` and aborting the retry loop.
  ADVERTISE_IP="$(docker compose $TS_FILES exec -T tailscale tailscale ip -4 2>/dev/null | head -n1 | tr -d '\r' || true)"
  [ -n "$ADVERTISE_IP" ] && break
  sleep 1
done

if [ -z "$ADVERTISE_IP" ]; then
  echo "[tailscale-lan] tailscale never reported an IP. Check:" >&2
  echo "    docker compose $TS_FILES logs tailscale" >&2
  exit 1
fi

echo "[tailscale-lan] tailnet IP = $ADVERTISE_IP"

# Persist it so every later `docker compose` command in this dir (logs,
# down, manual up) auto-loads it from .env — no need to re-export.
{
  echo "# Written by tailscale-lan.sh — the stack's tailnet IP for this run."
  echo "ADVERTISE_IP=$ADVERTISE_IP"
} > .env
export ADVERTISE_IP

echo "[tailscale-lan] bringing up kamailio + relay advertising $ADVERTISE_IP..."
docker compose $ALL_FILES up -d --build kamailio relay

cat <<EOF

[tailscale-lan] up. The stack advertises $ADVERTISE_IP (saved to .env).

Next:
  1. Install the Tailscale app on the phone and sign into the SAME tailnet.
  2. In the softphone use UDP, with STUN/ICE/SRTP off, and register:
         user:   <pick a unique AOR, e.g. bob>
         domain: $ADVERTISE_IP
  3. From the other softphone, dial sip:<that-user>@$ADVERTISE_IP

Logs:      docker compose $ALL_FILES logs -f kamailio relay
Tear down: docker compose $ALL_FILES down
EOF
