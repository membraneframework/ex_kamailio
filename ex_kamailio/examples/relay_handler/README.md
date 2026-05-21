# relay_handler

Two-peer RTP relay built on top of `ex_kamailio` and Membrane. The
`ExKamailio.Handler` callback hooks Kamailio's `rtpengine` commands
(offer / answer / delete) into a `Membrane.Pipeline` of two
`Membrane.UDP.Endpoint`s wired crosswise.

```
peer A  <-->  [UDP Endpoint]  <-x->  [UDP Endpoint]  <-->  peer B
              local: callee_local        local: caller_local
              dst:   caller_remote       dst:   callee_remote
```

(The unintuitive `caller_local`/`callee_local` mapping is the rtpengine
wire convention — `caller_local` is the port advertised in the rewritten
INVITE, which is the port the *callee* sends to.)

## Run end-to-end

The Docker rig at `docker/` is the canonical way to drive a real call —
it spins up Kamailio, two SIPp endpoints, and the relay itself in
containers. See [`docker/README.md`](docker/README.md) for the full
recipe. Quick version:

```sh
cd docker
docker compose up -d --build relay kamailio sipp-uas
docker compose run --rm sipp-uac
docker compose logs relay
```

## Run on the host (limited)

```sh
mix deps.get
MEDIA_IP=auto mix run --no-halt
```

This boots `ex_kamailio` on `:4003` with `RelayHandler` registered as
the command handler. Without Kamailio attached this won't see traffic.
On macOS, a host-run relay can't fully drive the Docker rig because the
host can't route UDP back to container bridge IPs — use the dockerized
flow above instead.

## Limitations

- RTP only — RTCP is not relayed yet.
- No latching — destinations come from each peer's SDP and are fixed.
  Symmetric-NAT peers won't work without latching.
- One pipeline per call; crash isolation is per-call.
