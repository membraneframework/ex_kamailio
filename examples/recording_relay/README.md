# recording_relay

An `ExKamailio.CallHandler` that relays RTP between the two peers of a call
through a Membrane pipeline and records both directions.

## Running the demo

Docker Compose runs Kamailio with the library's `kamailio.cfg` and the relay,
with SIP (5060) and the relay's RTP range (10000-10099) published, so the
stack is reachable on the local network at the machine's address. You need
Docker with Compose v2, ffmpeg for `ffplay`, and a phone to call from. The
first build takes a few minutes.

Docker Desktop needs nothing extra. Colima forwards only TCP by default, so
switch it to its gRPC forwarder once with `colima stop` and
`colima start --port-forwarder grpc`; the setting sticks.

1. Set `ADVERTISE_IP` to the machine's IP address in the local network and
   start the stack:

       cd docker
       echo ADVERTISE_IP=$(hostname -I | cut -d' ' -f1) > .env   # Linux
       echo ADVERTISE_IP=$(ipconfig getifaddr en0) > .env        # macOS
       docker compose up -d --build

2. Install Linphone on the machine and on a phone on the same Wi-Fi, register
   both as described below and call one from the other.

### Softphones

In Linphone, on the computer and on the phone, add a third-party SIP account
with:

- username: anything, different on each end
- password: anything, the Kamailio config checks no passwords
- domain: the `ADVERTISE_IP` above
- transport: UDP
- media encryption: none (Settings → Call)

Call the other end by its username. The recordings land in
`docker/recordings/`, one file per direction, and play with:

    ffplay -f alaw -ar 8000 recordings/<call_id>__offerer_to_answerer.raw

### Changing the code

The relay runs from its image, so after a change in `lib/` rebuild it with
`docker compose up -d --build`; nothing else needs a restart.

## How it works

`RecordingRelay` implements `ExKamailio.CallHandler`:

- `init/2` starts one `RecordingRelay.Pipeline` per call.
- `handle_offer/3` binds a UDP socket per peer, on the first free pair of
  ports from 10000-10099, and returns the offer with the relay's address and
  port in place of the offerer's.
- `handle_answer/3` points the answerer-facing socket at the answerer and
  returns the answer rewritten the same way.
- `handle_delete/2` stops the pipeline.

That way both peers send their RTP to the relay, and the pipeline passes it on
to the other peer and records it:

    {:socket, :offerer} -> {:tee, :offerer} -> {:socket, :answerer}
                                            -> RTP.Parser -> File.Sink (offerer_to_answerer.raw)

    {:socket, :answerer} -> {:tee, :answerer} -> {:socket, :offerer}
                                              -> RTP.Parser -> File.Sink (answerer_to_offerer.raw)

The sockets are `Membrane.UDP.Endpoint`s. The parser strips the RTP headers,
and the handler lets only G.711 A-law through, so
`docker/recordings/<call_id>__<direction>.raw` holds bare A-law at 8 kHz. On
an ordinary call the offerer is the caller.

## End-to-end test

`docker/e2e.sh` builds the images and starts the stack with a SIPp UAS
registered as `1000` that echoes back whatever RTP it receives. A SIPp UAC
then calls `1000` playing `g711a.pcap`, and the script checks that both
recordings hold exactly the pcap's payload:

    cd docker
    ./e2e.sh

The test keeps the stack on loopback whatever `.env` says, and touches only
its own recordings.

## Limitations

- Nothing is hardened: Kamailio accepts any REGISTER and the relay forwards
  whatever it gets. Keep the stack on a private network.
- One audio stream per call; any other m-line is rejected with port 0.
- G.711 A-law only; an offer without it is rejected with 488 Not Acceptable
  Here.
- Up to 50 calls at once, as the RTP range has 100 ports, and two calls set
  up at the same moment can grab the same pair.
- The relay sends to the address from a peer's SDP until that peer's packets
  arrive, then to wherever the latest one came from. A peer behind NAT
  therefore hears nothing until it has sent something, and the relay doesn't
  check who is sending.
