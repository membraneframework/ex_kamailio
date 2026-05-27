# Docker-based E2E for relay_handler

A five-service compose that runs a real SIP call between two SIPp endpoints
through Kamailio, with RTP relayed by a Membrane pipeline inside the
`relay_handler` container, and a small Membrane-based `sink` standing in
for the receiving peer's media socket so audio that crossed the relay can
be replayed afterwards.

```
  sipp-uac  ──INVITE──▶  kamailio  ◀───rtpengine ng (ws://relay:4003)───▶  relay_handler
     │                       │                                                 │
     │                       └──INVITE'──▶  sipp-uas                          (Membrane.UDP.Endpoint × 2)
     │                                                                         │
     └──────────────── RTP ────────────────▶ relay ◀──────── RTP ──────────────┘
                                              │
                                              └──── RTP ────▶ sink  ──▶ /recordings/uas.alaw
```

`sipp-uas` only handles SIP signaling. The SDP it sends back advertises
`sink`'s container IP (templated at startup) as the media address, so
rtpengine rewrites the answer accordingly and the relay forwards RTP to
`sink` instead of to sipp-uas. The sink is a 3-element Membrane pipeline
(`Membrane.UDP.Source → Membrane.RTP.Parser → Membrane.File.Sink`) that
strips RTP headers and writes the codec payload to a file.

## Why everything runs in containers

On macOS / Colima the host cannot route UDP to container bridge IPs
(`172.18.0.x`). A relay running on the host can *receive* RTP from peers
(they reach `host.docker.internal`), but it can't *deliver* RTP back to
the other peer. Putting the relay on the same docker network sidesteps
this entirely.

## Prerequisites

- Working Docker daemon (Colima recommended on macOS).

## Run

```sh
# Build images and start the long-running services.
docker compose up -d --build relay kamailio sink sipp-uas

# Place one call (UAC plays ~3s of a 440 Hz tone into the relay).
docker compose run --rm sipp-uac

# Listen to what arrived at the receiving peer.
ffplay -f alaw -ar 8000 -ac 1 recordings/uas.alaw

# Watch packet counters and pipeline lifecycle.
docker compose logs relay
```

Expected `relay` log lines:

```
[relay] offer  call=…  caller remote=… local=…
[relay] answer call=…  callee remote=… local=…
Pipeline<…> [relay] start call=…
Pipeline<…> [relay] call=… caller→callee=148 pkts, callee→caller=0 pkts
[relay] delete call=…
```

`caller→callee` counts the SIPp UAC's `play_pcap_audio` traffic transiting
the Membrane pipeline. `callee→caller` is 0 because the bundled UAS
scenario only listens. `sink` writes one `/recordings/uas.alaw` file per
run (overwritten between calls); restart the sink container if you want a
clean slate.

## Tear down

```sh
docker compose down
```

## What gets verified

- Kamailio loads `lwsc.so` and reaches `relay_handler` over WebSocket.
- The rtpengine `ng` protocol (offer / answer / delete) round-trips
  through `ExKamailio.WebSocket` and reaches `RelayHandler`.
- `RelayHandler.Pipeline` spawns on `answer`, binds the allocated RTP
  ports on the relay container's bridge interface, and tears down on
  `delete`.
- Real PCMA RTP from SIPp UAC arrives at the pipeline and is forwarded
  out the opposite UDP endpoint toward SIPp UAS.

## Limitations

- RTP only (no RTCP relay).
- Single-call demo. The relay handles multiple calls fine, but the
  scenario is `-m 1`.
