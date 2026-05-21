# relay_handler

Two-peer RTP relay built on top of `ex_kamailio` and a Membrane pipeline made
of a pair of `Membrane.UDP.Endpoint`s wired crosswise.

```
peer A  <-->  [UDP Endpoint A]  <-->  [UDP Endpoint B]  <-->  peer B
              local: caller_local      local: callee_local
              dst:   caller_remote     dst:   callee_remote
```

Kamailio handles signaling. ex_kamailio receives `offer`/`answer`/`delete`
commands over WebSocket, allocates local RTP ports, and invokes this handler.
On `answer` (when both peers' remotes are known), the handler spawns a
`RelayHandler.Pipeline` and hands the SDP answers back.

## Setup

```sh
mix deps.get
```

## Run

```sh
# Terminal 1: relay handler + ex_kamailio on the host
mix run --no-halt           # listens on :4003

# Terminal 2 & 3: Kamailio + SIPp — see ../echo_handler/docker/README.md
```

Replace `echo_handler` with `relay_handler` in the docker compose recipe.

## Limitations

- RTP only — RTCP is not relayed yet.
- No latching — destinations come from each peer's SDP and are fixed for the
  lifetime of the call. Symmetric-NAT peers will not work without latching.
- One pipeline per call. Crash isolation is per-call (one pipeline crash
  doesn't kill others).
