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

Docker Compose runs Kamailio with the library's `kamailio.cfg` and the relay,
with SIP (5060) and the relay's RTP range (10000-10099) published, so the
stack is reachable on the local network at the machine's address. You need
Docker with Compose v2, and ffmpeg for `ffplay`. The first build takes a few
minutes.

1. Put the machine's IP address on the local network (`ip -4 addr` on Linux,
   `ipconfig getifaddr en0` on macOS) in `docker/.env` and start the stack:

       cd docker
       echo ADVERTISE_IP=192.168.1.10 > .env
       docker compose up -d --build

2. Register two softphones on the same network as described below and call
   one from the other. One of them can run on the machine itself.

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
