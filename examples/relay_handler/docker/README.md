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

Both modes share the same Kamailio config and relay image. LAN mode
flips `network_mode` and takes the `#!ifdef LAN_MODE` branches in the
cfg: `rtpengine_sock` becomes loopback (`ws://127.0.0.1:4003`) instead
of docker DNS (`ws://relay:4003`), and the `advertise`/`alias` lines
for `$ADVERTISE_IP` are enabled (see "Call teardown" below).

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
`RTP.Parser → RTP.G711.Depayloader → G711.FFmpeg.Decoder → WAV.Serializer →
File.Sink` branch — a playable `.wav` per direction, proof on disk that
the bytes actually transited Membrane.

## Why everything runs in containers (Bridge mode)

On macOS / Colima the host cannot route UDP to container bridge IPs
(`172.18.0.x`). A relay on the host could receive RTP from peers
(they reach `host.docker.internal`) but can't deliver it back to the
other side. Putting the relay on the same docker network sidesteps
the problem entirely.

LAN mode escapes the bridge by joining `network_mode: host`, so
softphones reach Kamailio and the relay at `$ADVERTISE_IP` (a tailnet
IP by default — see "Reaching it from a real / mobile phone").

## Prerequisites

- Docker daemon (Colima recommended on macOS).
- `ffplay` (Homebrew: `brew install ffmpeg`) for playback.
- LAN mode with a real phone (default path): a Tailscale account and an
  auth key (free) — see "Reaching it from a real / mobile phone".

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
Pipeline<…> [relay] recording call=… to /recordings/…__caller_to_callee.wav / …
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
# pipeline, decoded to PCM and written as WAV — plays directly.
ffplay recordings/<call_id>__caller_to_callee.wav
```

(`-ch_layout mono` on the `uas.alaw` line is for ffmpeg 8.x; older ffmpeg
uses `-ac 1`.)

The sink keeps a single open fd on `uas.alaw` for its entire lifetime
— **do not `rm recordings/uas.alaw` while the sink container is
running**. Deleting the dirent leaves writes going to an unlinked
inode, and the file never reappears on disk. For a clean capture
between runs: `docker compose restart sink`.

The relay's per-call `.wav` files are opened fresh each call (one
pipeline = one open) so they're safe to delete between calls.

### Tear down

```sh
docker compose down
```

---

## LAN mode (real softphones)

Same compose stack, but `kamailio` and `relay` run in
`network_mode: host`. Softphones — including a **mobile phone** —
REGISTER and call each other through the relay.

### The one knob: `ADVERTISE_IP`

Everything reduces to a single env var. `ADVERTISE_IP` is the address
**every peer uses to reach this stack**; it fans out to both the SIP
advertise address (Record-Route / Via, so an in-dialog BYE routes
back) and the SDP media IP (so RTP routes back). The app is otherwise
network-agnostic — the only question is what reachable address to put
there, which depends on where the phones are.

### Reaching it from a real / mobile phone

Pick the row that matches your setup:

| Where are the peers?                            | How to fill `ADVERTISE_IP`                          |
|-------------------------------------------------|-----------------------------------------------------|
| **Anywhere** (phone on Wi-Fi *or cellular*, behind NAT) — **recommended, most reproducible** | **Tailscale** — `./tailscale-lan.sh` (below) |
| Linux host on a flat LAN                        | `export ADVERTISE_IP=$(hostname -I \| awk '{print $1}')`, then start |
| macOS, all devices on the *same* Wi-Fi          | bridged Colima VM (footnote below), then export its LAN IP |

#### Tailscale (default)

Works from any phone on any network without touching the router — the
steps are identical on macOS, Linux and Windows, which is what makes
it the reproducible default off a clean clone. A `tailscale` sidecar
(`compose.tailscale.yml`) joins the host netns and brings up a
`tailscale0` interface that the host-net `kamailio`/`relay` share.

```sh
# 1. Generate an auth key (ephemeral + pre-authorized recommended):
#      https://login.tailscale.com/admin/settings/keys
export TS_AUTHKEY=tskey-...

# 2. One command: brings up tailscale, resolves the tailnet IP into
#    ADVERTISE_IP, and starts kamailio + relay advertising it.
./tailscale-lan.sh
```

The script prints the `sip:` URI to point softphones at. Install the
**Tailscale app on the phone**, sign into the *same* tailnet, then
register a unique AOR at that address. (Requires a kernel TUN device in
the VM — the default Colima VM has `/dev/net/tun`.)

#### Bridged Colima VM (macOS, same-Wi-Fi only) — advanced footnote

If you specifically want the VM on your Wi-Fi L2 with a `192.168.x.y`
LAN IP and no VPN, recreate Colima with a bridged network
(`brew install qemu socket_vmnet`, `--vm-type qemu`, socket_vmnet in
bridged mode; needs sudo and is blocked on many routers / guest
networks), then `export ADVERTISE_IP=<the bridged IP>`. Tailscale is
preferred because it avoids all of that. Note the older
`colima --network-address` (vmnet *shared*) gives a `192.168.64.x` IP
reachable from the Mac only — fine for two softphones *on the Mac*, but
not from a separate phone.

If macOS firewall is on and SIP traffic never reaches Kamailio, allow
the relevant daemon in **System Settings → Privacy & Security →
Firewall**.

### Start (non-Tailscale paths)

```sh
export ADVERTISE_IP=<your reachable IP>
docker compose -f compose.yml -f compose.lan.yml up -d --build kamailio relay
```

`docker compose ps` should show both as `Up`. The other services in
`compose.yml` (`sink`, `sipp-*`) are not started in this mode — they
rely on docker DNS that doesn't apply once kamailio leaves the bridge.

### Configure the softphones

Same Kamailio, two SIP accounts on two devices (two apps on the Mac,
or one on the Mac and one on a phone). Both use UDP, no auth (our cfg
doesn't call `auth_check()`), any password (the form usually requires
non-empty — `x` is fine). Wherever the table below shows
`$ADVERTISE_IP`, type the address you set above (the tailnet IP from
`./tailscale-lan.sh`, or your LAN IP). On a phone, install the SIP app
(Linphone is on iOS/Android) and — for the Tailscale path — the
Tailscale app signed into the same tailnet.

> **Media encryption must be None on every client.** The relay does
> plain RTP only (no SRTP). If a softphone offers `RTP/SAVP` (SRTP), it
> gets a plain `RTP/AVP` answer and the *caller* drops the call the
> instant the callee answers. Disable SRTP/ZRTP/DTLS on both ends.

#### Linphone — Account A: alice

`brew install --cask linphone`, open it, click **Third-party SIP
account**:

| Field            | Value                             |
|------------------|-----------------------------------|
| Username         | `alice`                           |
| Password         | `x` (any non-empty)               |
| Domain           | `$ADVERTISE_IP`                   |
| Display name     | `Alice`                           |
| Transport        | **UDP**                           |
| Auth ID / Proxy / Registrar URI | leave empty                       |

In **Preferences → Network**: disable STUN, ICE, and SRTP.

#### Zoiper — Account B: carol

Download Zoiper Free from `zoiper.com`. The wizard will push you
toward provider lookup — work past it:

1. Username/Login: `carol@$ADVERTISE_IP`, Password: `x`, click Login.
2. When asked to pick a provider from a list, **don't** — keep the
   auto-filled hostname `$ADVERTISE_IP` and skip the provider step
   (button name varies; sometimes "Skip", sometimes a back arrow into
   a manual form).
3. Transport: **UDP**. Leave Auth and Outbound proxy **unchecked**.
4. Skip the "configure your Zoiper" walkthrough at the end.

Both accounts should show a green / "Registered" indicator within a
few seconds. If not, `docker compose -f compose.yml -f compose.lan.yml
logs kamailio` will show what arrived (or nothing).

### Place a call

From Linphone, with "From: Alice" selected, dial
`sip:carol@$ADVERTISE_IP`. Carol's device should ring; answer it.
Talking into the mic, you should hear your voice on the other device
(the relay ferries audio in both directions between the two apps).

### Verify media flowed through Membrane

`RelayHandler.Pipeline` decodes each direction to PCM and writes a WAV
to disk. After a call, list the recordings and play them back:

```sh
ls -la recordings/                 # *.wav files appear, one per direction
ffplay recordings/<call_id>__caller_to_callee.wav
ffplay recordings/<call_id>__callee_to_caller.wav
```

If those files exist and play back your actual voice from the call,
the audio definitely traversed the Membrane pipeline (not some
off-path UDP shortcut).

### Codec note

`ex_kamailio` itself is codec-agnostic; the `relay_handler` example *chooses*
to force PCMU by advertising payload types `[0, 101]` via
`SDP.answer_sdp/5` (see `RelayHandler.pcmu_sdp/1`) in both the offer and
answer it returns, so both peers are forced to PCMU regardless of what
they'd prefer (Opus, G.722, PCMA, …). PT 0 = PCMU (G.711 μ-law, 8 kHz,
mono) per RFC 3551; PT 101 = telephone-event for DTMF. The record branch
decodes that μ-law to PCM (`Membrane.RTP.G711.Depayloader →
Membrane.G711.FFmpeg.Decoder`) and serializes a WAV, so every relay-side
`.wav` plays directly. (Swap in `SDP.rewrite_endpoint/2` to forward the
peers' negotiated codecs instead — but then the record branch's hardcoded
PCMU decode would need to follow the negotiated codec too.)

### Call teardown (Record-Route / advertise address)

Because kamailio runs `network_mode: host` and binds `0.0.0.0`,
`record_route()` would otherwise stamp `sip:0.0.0.0` into the dialog —
an address the softphones can't route their in-dialog BYE to, so
hanging up one phone would never tear down the other (the relay
pipeline would linger as a zombie). The kamailio entrypoint in
`compose.lan.yml` fixes this by sed'ing `$ADVERTISE_IP` into the cfg's
`advertise` address, so Record-Route/Via point at a reachable address.
If you ever see calls that don't hang up, check the startup log line
`advertising <ip> in Record-Route/Via` and confirm `<ip>` is reachable
from the phones.

A second teardown trap: some UAs (e.g. Linphone desktop) answer with a
GRUU-style Contact at the proxy domain
(`sip:user@$ADVERTISE_IP;gr=...`), so the peer's in-dialog BYE comes
back addressed to kamailio itself and would loop on localhost instead
of reaching the callee. The cfg declares `$ADVERTISE_IP` as an `alias`
and re-resolves such self-addressed in-dialog requests via
`lookup("location")`, so a hangup from either side tears down both.

### Tear down

```sh
# Tailscale path (tailscale-lan.sh wrote .env, so ADVERTISE_IP resolves):
docker compose -f compose.yml -f compose.lan.yml -f compose.tailscale.yml down

# Non-Tailscale path:
docker compose -f compose.yml -f compose.lan.yml down
```

---

## Configuration seams

| Concern                              | Where                                      |
|--------------------------------------|--------------------------------------------|
| SDP-advertised media IP              | `MEDIA_IP` env in compose (bridge = `auto`, the container's own IP; LAN = `$ADVERTISE_IP`) |
| Reachable address for real phones    | `$ADVERTISE_IP` — set by `tailscale-lan.sh` (tailnet IP) or exported manually; the single knob for both SIP + media |
| Registrar destination (relay)        | `kamailio.cfg`, `rtpengine_sock` line — `#!ifdef LAN_MODE` selects loopback vs docker DNS |
| SIP advertise address (LAN)          | `kamailio.cfg` `listen ... advertise ADVERTISE_PLACEHOLDER` — sed'd to `$ADVERTISE_IP` by the kamailio entrypoint; fixes in-dialog BYE routing |
| In-dialog requests to GRUU/proxy Contacts | `kamailio.cfg` — `alias` + `if (uri==myself) lookup("location")` re-resolves them to the real binding so BYE/ACK reach the callee |
| Relay readiness gate                 | `compose.yml` — relay `healthcheck` (port 4003) + kamailio `depends_on: condition: service_healthy`, so kamailio's rtpengine link doesn't race the relay's boot |
| Relay UDP port range                 | `ex_kamailio` `port_range` config (`config/config.exs`) |
| Codec / payload types                | `RelayHandler.pcmu_sdp/1` — `[0, 101]` via `SDP.answer_sdp/5` |
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
- The example forces PCMU in `RelayHandler.pcmu_sdp/1`. Anything
  else gets dropped during negotiation.
- Bridge-mode SIPp self-test is `-m 1` (single call). The stack
  handles multiple calls fine.
- Reaching the stack from a separate device needs a routable
  `ADVERTISE_IP`. Tailscale (default) handles this on any network; the
  bridged-VM and Linux-host alternatives are documented under "Reaching
  it from a real / mobile phone".
- The Tailscale sidecar needs a kernel TUN device (`/dev/net/tun`) in
  the VM; userspace mode would not expose `tailscale0` to the other
  containers.
