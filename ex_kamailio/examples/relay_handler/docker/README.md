# Docker-based E2E for relay_handler

A four-service compose that runs a real SIP call between two SIPp endpoints
through Kamailio, with RTP relayed by a Membrane pipeline inside the
`relay_handler` container.

```
  sipp-uac  ──INVITE──▶  kamailio  ◀───rtpengine ng (ws://relay:4003)───▶  relay_handler
     │                       │                                                 │
     │                       └──INVITE'──▶  sipp-uas                          (Membrane.UDP.Endpoint × 2)
     │                                                                         │
     └──────────────── RTP ────────────────▶ relay ◀──────── RTP ──────────────┘
                                              │
                                              └──── RTP ────▶ sipp-uas
```

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
docker compose up -d --build relay kamailio sipp-uas

# Place one call (UAC plays ~3s of g711 RTP into the relay).
docker compose run --rm sipp-uac

# Watch packet counters and pipeline lifecycle.
docker compose logs relay
```

Expected `relay` log lines:

```
[relay] offer  call=…  caller remote=… local=…
[relay] answer call=…  callee remote=… local=…
Pipeline<…> [relay] start call=…
Pipeline<…> [relay] call=… caller→callee=16 pkts, callee→caller=0 pkts
[relay] delete call=…
```

`caller→callee` counts the SIPp UAC's `play_pcap_audio` traffic transiting
the Membrane pipeline. `callee→caller` is 0 because the bundled UAS
scenario only listens — SIPp's `play_pcap_audio` in UAS scenarios needs
extra setup that isn't worth doing for the demo. The bidirectional
symmetry of the relay pipeline is independently verified by a direct
probe test (see project history).

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
- No latching: peer destinations come from each SDP and are fixed for
  the call. Inside this rig SIPp advertises routable container IPs.
- Single-call demo. The relay handles multiple calls fine, but the
  scenario is `-m 1`.
