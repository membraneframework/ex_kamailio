# recording_relay

An `ExKamailio.CallHandler` that relays RTP between the two peers of a call
through a Membrane pipeline and records both directions.

## Running the demo

Docker Compose runs the relay and Kamailio with the library's `kamailio.cfg`,
and publishes SIP on 5060 and the relay's RTP range 10000-10099, so the stack
is reachable on the local network at the machine's address. You need
Docker with Compose v2, ffmpeg for `ffplay`, and a phone to call from. The
first build takes a few minutes.

Docker Desktop needs nothing extra. Colima forwards only TCP by default, so
switch it to its gRPC forwarder once with `colima stop` and
`colima start --port-forwarder grpc`; the setting sticks.

1. Set `ADVERTISE_IP` to the machine's address on the local network and
   start the stack.

   Linux:

       cd docker
       echo ADVERTISE_IP=$(hostname -I | cut -d' ' -f1) > .env
       docker compose up -d --build

   macOS:

       cd docker
       echo ADVERTISE_IP=$(ipconfig getifaddr en0) > .env
       docker compose up -d --build

2. Install Linphone on the machine and on a phone on the same Wi-Fi, and add
   a third-party SIP account on each with:

   - username: anything, different on each peer
   - password: anything, the Kamailio config checks no passwords
   - domain: the `ADVERTISE_IP` above
   - transport: UDP
   - media encryption: none (Settings → Call)

3. Call the other peer by its username. Each call leaves two files in
   `recordings/`, one per direction; the offerer is the caller. Play one with:

       ffplay -f alaw -ar 8000 recordings/<call_id>__offerer_to_answerer.raw

### Changing the code

The relay runs from its image: after a code change,
`docker compose up -d --build` rebuilds it and recreates Kamailio with it.

## How it works

`RecordingRelay` implements `ExKamailio.CallHandler`:

- `init/2` starts one `RecordingRelay.Pipeline` per call, which picks the
  first free pair of ports from 10000-10099.
- `handle_offer/3` binds a UDP socket per peer and returns the offer with the
  relay's address and the answerer-facing port in place of the offerer's.
- `handle_answer/3` points the answerer-facing socket at the answerer and
  returns the answer rewritten the same way.
- `handle_delete/2` stops the pipeline.

That way both peers send their RTP to the relay, and the pipeline passes it on
to the other peer and records it:

    {:socket, :offerer} -> {:tee, :offerer} -> {:socket, :answerer}
                                            -> RTP.Parser -> File.Sink (offerer_to_answerer.raw)

    {:socket, :answerer} -> {:tee, :answerer} -> {:socket, :offerer}
                                              -> RTP.Parser -> File.Sink (answerer_to_offerer.raw)

The parser strips the RTP headers, and the handler lets only G.711 A-law
through, so `recordings/<call_id>__<direction>.raw` holds bare A-law at 8 kHz.

## End-to-end test

`docker/e2e.sh` builds the images and starts the stack with a SIPp UAS
registered as `1000` that echoes back whatever RTP it receives. A SIPp UAC
then calls `1000` playing `g711a.pcap`, and the script checks that both
recordings have the size of the pcap's payload and are identical:

    cd docker
    ./e2e.sh

The test advertises 127.0.0.1 whatever `.env` says, and deletes only its own
recordings.

## Limitations

- Nothing is hardened: Kamailio accepts any REGISTER and the relay forwards
  whatever it gets. Keep the stack on a private network.
- One audio stream per call; any other m-line is rejected with port 0.
- G.711 A-law only; an offer without it is rejected with 488 Not Acceptable
  Here.
- Up to 50 calls at once: the RTP range has 100 ports. Two calls set up at
  the same moment can grab the same pair.
- The relay sends to the address from a peer's SDP until that peer's packets
  arrive, then to wherever the latest one came from. A peer behind NAT
  therefore hears nothing until it has sent something, and the relay doesn't
  check who is sending.
