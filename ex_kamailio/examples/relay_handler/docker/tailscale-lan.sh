#!/usr/bin/env bash
#
# Bring the Kamailio + relay stack up reachable over Tailscale: start the
# sidecar, resolve its tailnet IP into ADVERTISE_IP, then start kamailio +
# relay advertising it. Needs TS_AUTHKEY exported. See README.md.

set -euo pipefail
cd "$(dirname "$0")"

: "${TS_AUTHKEY:?generate an auth key at https://login.tailscale.com/admin/settings/keys, then: export TS_AUTHKEY=tskey-...}"

# Sidecar comes up with only the tailscale file: the full set can't be parsed
# yet (it requires ADVERTISE_IP, which the sidecar hasn't produced).
TS_FILES="-f compose.tailscale.yml"
ALL_FILES="-f compose.yml -f compose.lan.yml -f compose.tailscale.yml"

echo "[tailscale-lan] starting tailscale sidecar..."
docker compose $TS_FILES up -d tailscale

echo "[tailscale-lan] waiting for a tailnet IPv4 (auth can take a few seconds)..."
ADVERTISE_IP=""
for _ in $(seq 1 60); do
  # `|| true`: a probe before tailscaled is authed must not trip `set -e`.
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

# Persist to .env so later docker compose commands (logs, down) auto-load it.
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
