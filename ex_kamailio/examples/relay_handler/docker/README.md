# Docker rig for relay_handler

A compose-based test rig that runs Kamailio + the Membrane RTP relay
together, in two modes:

- **Bridge mode** (`compose.yml`) — fully self-contained Docker E2E:
  two SIPp endpoints, Kamailio, the Membrane relay, and a sink that
  records what arrives on the far side. No external clients needed.
- **LAN mode** (`compose.yml` + `compose.lan.yml`) — Kamailio and the
  relay run on the Colima VM's host network so real softphones on
  your Mac (Linphone, Zoiper, …) can REGISTER and call each other
  through the same stack.

Both modes share the same Kamailio config and relay image; LAN mode
only flips `network_mode` and toggles a `#!ifdef LAN_MODE` block in
the cfg that switches `rtpengine_sock` between docker DNS
(`ws://relay:4003`) and loopback (`ws://127.0.0.1:4003`).

## Architecture

```
  sipp-uac  ──INVITE──▶  kamailio  ◀───rtpengine ng (ws)───▶  relay (Membrane)
     │                       │                                     │
     │                       └──INVITE'──▶  sipp-uas             (UDP × 2 legs)
     │                                                              │
     └──────────────── RTP ────────────────▶ relay ◀──── RTP ───────┘
                                              │
                                              ├── /recordings/<call_id>__…_to_…raw
                                              └── (LAN) ──▶ Linphone / Zoiper / …
```

`sipp-uas` only handles SIP signalling — its answer SDP advertises
`sink`'s container IP (templated at startup), so rtpengine rewrites
the answer accordingly and the relay forwards RTP to `sink` rather
than to sipp-uas itself. Sink is a 3-element Membrane pipeline
(`UDP.Source → RTP.Parser → File.Sink`) that strips RTP headers and
writes the codec payload to disk.

The relay pipeline itself (`RelayHandler.Pipeline`) also writes one
recording **per direction, per call**, using a `Tee.Parallel` that
fans each leg's output into both the other leg (forward) and a
`RTP.Parser → File.Sink` branch — proof on disk that the bytes
actually transited Membrane.

## Why everything runs in containers (Bridge mode)

On macOS / Colima the host cannot route UDP to container bridge IPs
(`172.18.0.x`). A relay on the host could receive RTP from peers
(they reach `host.docker.internal`) but can't deliver it back to the
other side. Putting the relay on the same docker network sidesteps
the problem entirely.

LAN mode escapes the bridge by joining `network_mode: host`, so
softphones outside the VM reach Kamailio and the relay at the
Colima VM's LAN IP.

## Prerequisites

- Docker daemon (Colima recommended on macOS).
- `ffplay` (Homebrew: `brew install ffmpeg`) for playback.
- LAN mode only: Colima started with `--network-address` (one-time,
  needs sudo) so the VM has a real LAN-reachable IP.

---

## Bridge mode (Docker-only)

Self-contained E2E. Two SIPp endpoints, one Kamailio, the relay, and
a sink — all on a shared docker network. Good for regression checks.

### Run

```sh
# Build images and start the long-running services.
docker compose up -d --build relay kamailio sink sipp-uas

# REGISTER user 1000 (one-shot) so Kamailio's lookup("location") has a
# binding to route INVITEs to.
docker compose run --rm sipp-register

# Place one call. UAC plays a ~10-second PCMA melody into the relay.
docker compose run --rm sipp-uac

# Watch packet counters and pipeline lifecycle.
docker compose logs relay
```

### Expected `relay` log lines

```
[relay] offer  call=…  caller remote=… local=…
[relay] answer call=…  callee remote=… local=…
Pipeline<…> [relay] start call=…
Pipeline<…> [relay] recording call=… to /recordings/…__caller_to_callee.raw / …
Pipeline<…> [relay] call=… caller→callee=499 pkts, callee→caller=0 pkts
[relay] delete call=…
```

`caller→callee` counts the SIPp UAC's `play_pcap_audio` traffic
transiting the Membrane pipeline. `callee→caller` is 0 because the
bundled UAS scenario only listens — it doesn't send media.

### Recordings

Two files are produced per call:

```sh
# The sink container records the audio that arrived at the receiving peer.
# (PCMA fixture played by the UAC; see sipp/gen_tone_pcap.sh.)
ffplay -f alaw -ar 8000 -ch_layout mono recordings/uas.alaw

# The relay's Tee branch records each direction transiting the Membrane
# pipeline. PCMU (μ-law) — see "Codec note" below.
ffplay -f mulaw -ar 8000 -ch_layout mono recordings/<call_id>__caller_to_callee.raw
```

(`-ch_layout mono` is for ffmpeg 8.x; older ffmpeg uses `-ac 1`.)

The sink keeps a single open fd on `uas.alaw` for its entire lifetime
— **do not `rm recordings/uas.alaw` while the sink container is
running**. Deleting the dirent leaves writes going to an unlinked
inode, and the file never reappears on disk. For a clean capture
between runs: `docker compose restart sink`.

The relay's per-call `.raw` files are opened fresh each call (one
pipeline = one open) so they're safe to delete between calls.

### Tear down

```sh
docker compose down
```

---

## LAN mode (real softphones)

Same compose stack but `kamailio` and `relay` run in
`network_mode: host`, joining the Colima VM's network namespace.
Softphones on your Mac (or anywhere on the LAN that can reach the VM)
REGISTER at the VM's LAN IP and call each other through the relay.

### One-time Colima setup

```sh
colima stop && colima start --network-address
colima list   # ADDRESS column = the VM's LAN IP
```

`--network-address` uses vmnet to assign the VM a real IP from a
shared subnet (typically `192.168.64.x`). This needs sudo once. The
default vmnet "shared" mode is reachable from the Mac itself but **not
from other devices on your Wi-Fi**; for phone-to-Mac calls switch to
vmnet bridged (different flag set; not covered here yet).

If macOS firewall is on and you don't see SIP traffic reach Kamailio
later, allow Colima / the vmnet daemon in **System Settings → Privacy
& Security → Firewall**.

### Start

```sh
export COLIMA_LAN_IP=192.168.64.2   # from `colima list`
docker compose -f compose.yml -f compose.lan.yml up -d --build kamailio relay
```

`docker compose ps` should show both as `Up`. The other services in
`compose.yml` (`sink`, `sipp-*`) are not started in this mode — they
rely on docker DNS that doesn't apply once kamailio leaves the bridge.

### Configure two softphones on the Mac

Same Kamailio, two SIP accounts. Both use UDP, no auth (our cfg
doesn't call `auth_check()`), any password (the form usually requires
non-empty — `x` is fine).

#### Linphone — Account A: alice

`brew install --cask linphone`, open it, click **Third-party SIP
account**:

| Field            | Value                             |
|------------------|-----------------------------------|
| Username         | `alice`                           |
| Password         | `x` (any non-empty)               |
| Domain           | `192.168.64.2` (or your IP)       |
| Display name     | `Alice`                           |
| Transport        | **UDP**                           |
| Auth ID / Proxy / Registrar URI | leave empty                       |

In **Preferences → Network**: disable STUN, ICE, and SRTP.

#### Zoiper — Account B: carol

Download Zoiper Free from `zoiper.com`. The wizard will push you
toward provider lookup — work past it:

1. Username/Login: `carol@192.168.64.2`, Password: `x`, click Login.
2. When asked to pick a provider from a list, **don't** — keep the
   auto-filled hostname `192.168.64.2` and skip the provider step
   (button name varies; sometimes "Skip", sometimes a back arrow into
   a manual form).
3. Transport: **UDP**. Leave Auth and Outbound proxy **unchecked**.
4. Skip the "configure your Zoiper" walkthrough at the end.

Both accounts should show a green / "Registered" indicator within a
few seconds. If not, `docker compose -f compose.yml -f compose.lan.yml
logs kamailio` will show what arrived (or nothing).

### Place a call

From Linphone, with "From: Alice" selected, dial
`sip:carol@192.168.64.2`. Zoiper should ring; answer it. Talking into
the mic, you should hear your own voice on the speakers (the relay
ferries audio in both directions between the two apps).

### Verify media flowed through Membrane

`RelayHandler.Pipeline` writes the codec payload of each direction
to disk. After a call, list the recordings and play them back:

```sh
ls -la recordings/                 # *.raw files appear, one per direction
ffplay -f mulaw -ar 8000 -ch_layout mono \
       recordings/<call_id>__caller_to_callee.raw
ffplay -f mulaw -ar 8000 -ch_layout mono \
       recordings/<call_id>__callee_to_caller.raw
```

If those files exist and play back your actual voice from the call,
the audio definitely traversed the Membrane pipeline (not some
off-path UDP shortcut).

### Codec note

The handler hardcodes `[0, 101]` as the payload types it advertises in
the answer SDP (see `RelayHandler.answer_for/1`), so both peers are
forced to PCMU regardless of what they'd prefer (Opus, G.722, PCMA,
…). PT 0 = PCMU (G.711 μ-law, 8 kHz, mono) per RFC 3551; PT 101 =
telephone-event for DTMF. That's why every relay-side `.raw`
recording is μ-law and `ffplay -f mulaw -ar 8000 -ch_layout mono`
always works.

### Tear down

```sh
docker compose -f compose.yml -f compose.lan.yml down
```

---

## Configuration seams

| Concern                              | Where                                      |
|--------------------------------------|--------------------------------------------|
| SDP-advertised media IP              | `MEDIA_IP` env in compose (bridge = `relay` docker name; LAN = `$COLIMA_LAN_IP`) |
| Registrar destination (relay)        | `kamailio.cfg`, `rtpengine_sock` line — `#!ifdef LAN_MODE` selects loopback vs docker DNS |
| Relay UDP port range                 | `ex_kamailio` `port_range` config (`config/config.exs`) |
| Codec / payload types                | `RelayHandler.answer_for/1` — `[0, 101]`  |
| Per-call recordings location         | `RelayHandler.Pipeline` — `@recordings_dir`, mounted from `./recordings` |

## Rollback

The last commit before the REGISTER/lookup work is tagged
`relay-docker-e2e-v1` — known-good bridge-mode E2E.

```sh
git checkout relay-docker-e2e-v1     # known-good Docker E2E
git diff   relay-docker-e2e-v1..HEAD # what changed since
```

## Limitations

- RTP only — RTCP is not relayed.
- PCMU codec is hardcoded in `RelayHandler.answer_for/1`. Anything
  else gets dropped during negotiation.
- Bridge-mode SIPp self-test is `-m 1` (single call). The stack
  handles multiple calls fine.
- vmnet shared (default for `--network-address`) reaches the Mac
  only, not other LAN devices. Use vmnet bridged for real phones on
  Wi-Fi.
