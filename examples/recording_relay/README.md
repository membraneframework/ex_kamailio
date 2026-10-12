# recording_relay

An `ExKamailio.CallHandler` that relays RTP between the two peers of a call
through a Membrane pipeline and records both directions. ex_kamailio only
shuttles SDP between Kamailio and your code; the media is the handler's job.
This one does the minimum:

- `init/2` starts one `RecordingRelay.Pipeline` per call.
- `handle_offer/3` binds a UDP socket per peer and returns the offer with the
  relay's address and port in place of the offerer's.
- `handle_answer/3` points the answerer-facing socket at the answerer and
  returns the answer rewritten the same way.
- `handle_delete/2` stops the pipeline.

The pipeline cross-links two `Membrane.UDP.Endpoint`s, so whatever one peer
sends goes out to the other, and records each direction's raw RTP payload to
`docker/recordings/<call_id>__<from>_to_<to>.raw`. The handler lets only
G.711 A-law through, so every recording plays with:

    ffplay -f alaw -ar 8000 docker/recordings/<call_id>__offerer_to_answerer.raw

## Running it

The stack is Docker Compose on the host network: Kamailio with the library's
`kamailio.cfg`, the relay, and a SIPp UAS registered as `1000` that echoes
back whatever RTP it receives. `ADVERTISE_IP` in `docker/.env` is the address
the phones reach it at; unset, everything stays on loopback. You need Docker
with Compose v2, and ffmpeg for `ffplay`. The first build takes a few minutes.

### Linux

1. Run the end-to-end test. It builds the images, places one call with SIPp
   playing `g711a.pcap` and checks that both recordings hold exactly the
   pcap's payload:

       cd docker
       ./e2e.sh

2. Put the machine's LAN address in `.env` and start the stack there, so that
   phones reach it:

       echo ADVERTISE_IP=192.168.1.10 > .env
       docker compose up -d --build

3. Set up a softphone as described below and call `1000`.

### macOS

Docker runs in a Linux VM here, so the host network is the VM's, and no
other device can reach it. The stack joins a tailnet instead, and so do the
phones. Tested with Colima; Docker Desktop needs host networking enabled in
its settings and is untested.

1. Run the end-to-end test, as on Linux:

       cd docker
       ./e2e.sh

2. Start the tailscale sidecar and log it into your tailnet with the URL it
   prints (a free account will do):

       docker compose --profile tailscale up -d tailscale
       docker compose logs tailscale

3. Put the VM's tailnet address in `.env` and start the stack there:

       echo ADVERTISE_IP=$(docker compose exec -T tailscale tailscale ip -4) > .env
       docker compose up -d --build

4. Install Tailscale on the phone and log into the same tailnet. Then set up
   a softphone as described below and call `1000`. A softphone on the Mac
   works the same way once the Mac is on the tailnet.

### Softphones

In Linphone, add a third-party SIP account with:

- username and password: anything, the Kamailio config checks no passwords
- domain: the `ADVERTISE_IP` above
- transport: UDP
- media encryption: none (Settings → Call)

`1000` echoes your voice back through the relay, and two registered
softphones can call each other.

### Changing the handler

The relay runs from the image, so after editing `lib/` rebuild it with
`docker compose up -d --build`. Kamailio and the UAS restart with it, as
Kamailio does not reconnect to a restarted relay. For a quick check without
Docker, `mix deps.get && mix compile`.

## Limitations

- Nothing is hardened: Kamailio accepts any REGISTER and the relay forwards
  whatever it gets. Keep the stack on a private network.
- One audio stream per call; any other m-line is rejected with port 0.
- G.711 A-law only; an offer without it is rejected with 488 Not Acceptable
  Here.
- Peers behind NAT get their audio once they have sent some: the relay sends
  to the address from the SDP until packets arrive, then to wherever they come
  from. Nothing checks who sends them.
