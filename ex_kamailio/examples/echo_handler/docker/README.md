# Docker-based E2E test for ex_kamailio

Spin up real Kamailio (with `rtpengine` + `lwsc` modules) and a pair of
SIPp endpoints to drive a one-shot SIP call end-to-end through
ex_kamailio. Works on macOS via Colima or Docker Desktop — Kamailio
talks to ex_kamailio running on the host via `host.docker.internal:4003`.

## What it verifies

- Kamailio loads `lwsc.so` and opens a real WebSocket to ex_kamailio.
- The rtpengine `ng` Bencode protocol flows correctly: `offer` →
  `answer` → `delete` commands all reach `ExKamailio.Handler` with
  matching call-ids.
- ex_kamailio's port allocation, SDP parsing, and session bookkeeping
  hold up against actual SIP signaling.

It does **not** verify media — the SIPp scenarios never emit real RTP
and the echo_handler doesn't bridge any. To exercise the media path,
swap in a real handler that wires the allocated ports into a pipeline.

## Prerequisites

- A working Docker daemon (Colima recommended on macOS):
  ```sh
  brew install colima docker docker-compose
  colima start --runtime docker --kubernetes=false
  ```
- ex_kamailio compiled in this checkout.

## Run

```sh
# Terminal 1: ex_kamailio + echo_handler on the host
cd ..        # ex_kamailio/examples/echo_handler
mix deps.get
mix run --no-halt        # listens on :4003

# Terminal 2: Kamailio + SIPp UAS
cd docker
docker compose up -d kamailio sipp-uas

# Terminal 3: place one call
docker compose run --rm sipp-uac
```

Watch terminal 1 for `[echo] offer …`, `[echo] answer …`,
`[echo] delete …` log lines — those are Kamailio rtpengine commands
arriving via WebSocket.

## Tear down

```sh
docker compose down
```

## Notes

- **Why `host.docker.internal`?** ex_kamailio runs on the macOS host;
  Kamailio runs in a container. The compose file adds an
  `extra_hosts` mapping so the name resolves correctly under Colima
  (Docker Desktop sets it automatically).
- **"unknown call" warnings in Kamailio logs are normal.** Kamailio's
  multiple worker processes retry rtpengine commands on retransmits.
  Once a session is in `:answered` state, ex_kamailio rejects further
  `answer` requests with "unknown call" — semantically correct, just
  log-noisy on Kamailio's side.
- **SDP IPs may show `0.0.0.0`.** SIPp inside a container doesn't
  always pick a sensible `[media_ip]`. Doesn't affect the protocol
  test; a real SIP client would advertise its real address.
