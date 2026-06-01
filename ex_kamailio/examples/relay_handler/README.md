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

Each leg's output also fans through a `Membrane.Tee.Parallel` into an
`RTP.Parser → File.Sink` branch, so every bridged call drops two
per-direction recordings into `docker/recordings/` —
`<call_id>__caller_to_callee.raw` and `<call_id>__callee_to_caller.raw`.
That's the on-disk proof that the audio actually transited the
Membrane pipeline. The codec is hardcoded to **PCMU** (G.711 μ-law,
8 kHz, mono) by `RelayHandler.answer_for/1`, so playback is always:

```sh
ffplay -f mulaw -ar 8000 -ch_layout mono \
       docker/recordings/<call_id>__caller_to_callee.raw
```

(`-ch_layout mono` is for ffmpeg 8.x; older ffmpeg uses `-ac 1`.)

## Run end-to-end

The Docker rig at `docker/` is the canonical way to drive a real
call. It supports two modes:

- **Bridge mode** — fully self-contained Docker E2E (SIPp UAC, SIPp
  UAS, Kamailio, relay, sink). Good for regression checks; no
  external clients needed.
- **LAN mode** — Kamailio and relay on the Colima VM's host network,
  with real softphones on the Mac (Linphone, Zoiper) calling each
  other through the same stack.

Quick version (bridge mode):

```sh
cd docker
docker compose up -d --build relay kamailio sink sipp-uas
docker compose run --rm sipp-register   # populate Kamailio's usrloc
docker compose run --rm sipp-uac        # place the call
ffplay -f alaw -ar 8000 -ch_layout mono recordings/uas.alaw
```

See [`docker/README.md`](docker/README.md) for the full recipe of
both modes, the softphone configuration, and rollback / codec /
caveats notes.

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
- PCMU codec is hardcoded in `RelayHandler.answer_for/1`.
- One pipeline per call; crash isolation is per-call.
