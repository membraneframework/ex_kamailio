# recording_relay

An `ExKamailio.CallHandler` that relays RTP between the two peers of a call
through a Membrane pipeline and records both directions.

- `init/2` starts one `RecordingRelay.Pipeline` per call.
- `handle_offer/3` binds a UDP socket per peer and returns the offer with the
  relay's address and port in place of the offerer's.
- `handle_answer/3` points the answerer-facing socket at the answerer and
  returns the answer rewritten the same way.
- `handle_delete/2` stops the pipeline.

The pipeline forwards whatever one peer sends to the other and writes each
direction, with the RTP headers stripped, to
`docker/recordings/<call_id>__offerer_to_answerer.raw` and
`<call_id>__answerer_to_offerer.raw`; on an ordinary call the offerer is the
caller. The handler lets only G.711 A-law through, so every recording is plain
A-law and plays with:

    ffplay -f alaw -ar 8000 docker/recordings/<call_id>__offerer_to_answerer.raw

## Running the demo

Docker Compose runs Kamailio with the library's `kamailio.cfg` and the relay
on the host network. `ADVERTISE_IP` in `docker/.env` is the address the
phones reach them at. You need Docker with Compose v2, and ffmpeg for
`ffplay`. The first build takes a few minutes.

### Linux

1. Put the machine's LAN address in `.env` and start the stack:

       cd docker
       echo ADVERTISE_IP=192.168.1.10 > .env
       docker compose up -d --build

2. Register two softphones as described below and call one from the other.

### macOS

Docker runs in a Linux VM here, so the host network is the VM's, and no
other device can reach it. The stack joins a tailnet instead, and so do the
phones. Docker Desktop has host networking off by default; turn it on in its
settings. Tested with Colima.

1. Start the tailscale sidecar and log it into your tailnet with the URL it
   prints (a free account will do):

       cd docker
       docker compose --profile tailscale up -d tailscale
       docker compose logs tailscale

2. Put the VM's tailnet address in `.env` and start the stack:

       echo ADVERTISE_IP=$(docker compose exec -T tailscale tailscale ip -4) > .env
       docker compose up -d --build

3. Install Tailscale on the phones, or on the Mac for a softphone there, and
   log into the same tailnet. Then register two softphones as described below
   and call one from the other.

### Softphones

In Linphone, add a third-party SIP account with:

- username: anything, different on each phone
- password: anything, the Kamailio config checks no passwords
- domain: the `ADVERTISE_IP` above
- transport: UDP
- media encryption: none (Settings → Call)

Call the other phone by its username. The recordings land in
`docker/recordings/`.

### Changing the code

The relay runs from its image, so after a change in `lib/` rebuild it with
`docker compose up -d --build`; nothing else needs a restart.

## End-to-end test

`docker/e2e.sh` builds the images and starts the stack with a SIPp UAS
registered as `1000` that echoes back whatever RTP it receives. A SIPp UAC
then calls `1000` playing `g711a.pcap`, and the script checks that both
recordings hold exactly the pcap's payload:

    cd docker
    ./e2e.sh

Without `.env` the stack stays on loopback, which is all the test needs.

## Limitations

- Nothing is hardened: Kamailio accepts any REGISTER and the relay forwards
  whatever it gets. Keep the stack on a private network.
- One audio stream per call; any other m-line is rejected with port 0.
- G.711 A-law only; an offer without it is rejected with 488 Not Acceptable
  Here.
- Peers behind NAT get their audio once they have sent some: the relay sends
  to the address from the SDP until packets arrive, then to wherever they come
  from. Nothing checks who sends them.
