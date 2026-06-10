# relay_handler

Two-peer RTP relay built on top of `ex_kamailio` and Membrane. The
`ExKamailio.Handler` callbacks hook Kamailio's `rtpengine` commands
(offer / answer / delete) into a `Membrane.Pipeline` that grows one
unidirectional leg at a time as the SIP dialog progresses.

`ex_kamailio` is a pure SDP shuttle — it allocates no ports and owns no media.
This example owns all of that: it keeps its own `RelayHandler.PortPool`, picks
the local ports, and binds the sockets.

```
offer:  answerer → UDP.Source(:offerer_local) ─tee─▶ UDP.Sink ─▶ offerer
                                                   └▶ answerer_to_offerer.wav
answer: offerer → UDP.Source(:answerer_local) ─tee─▶ UDP.Sink ─▶ answerer
                                                   └▶ offerer_to_answerer.wav
```

On `offer` the handler picks `offerer_local` (the port advertised in the
rewritten INVITE — the port the *answerer* sends to) and starts the
answerer→offerer leg. On `answer` it picks `answerer_local` (the port the
*offerer* sends to) and adds the offerer→answerer leg to the running pipeline.
(`<role>_local` names the leg by the SDP exchange that allocated it.)

Each leg's output also fans through a `Membrane.Tee.Parallel` into a
`RTP.Parser → RTP.G711.Depayloader → G711.FFmpeg.Decoder → WAV.Serializer →
File.Sink` branch, so every bridged call drops two per-direction recordings
into `docker/recordings/` — `<call_id>__offerer_to_answerer.wav` and
`<call_id>__answerer_to_offerer.wav`. That's the on-disk proof that the audio
actually transited the Membrane pipeline. `RelayHandler` forces **PCMU**
(G.711 μ-law, 8 kHz, mono) in the SDP it returns; the record branch decodes
it to PCM and writes a standard WAV header, so the files play directly:

```sh
ffplay docker/recordings/<call_id>__offerer_to_answerer.wav   # or any player
```

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
- Codecs are whatever the two peers negotiate; recordings/playback assume
  PCMU (μ-law). ex_kamailio forwards the SDP, it doesn't transcode.
- One pipeline per call, kept in the handler's per-call state.
