# relay_handler

An `ExKamailio.CallHandler` that relays RTP between the two peers of a call
through a Membrane pipeline. ex_kamailio only shuttles SDP between Kamailio and
your code; the media is the handler's job, and this example does the minimum
of it:

- `init/2` starts one `RelayHandler.Pipeline` per call.
- `handle_offer/3` binds a UDP socket per peer and returns the offer with the
  relay's address and port in place of the offerer's.
- `handle_answer/3` points the answerer-facing socket at the answerer and
  returns the answer rewritten the same way.
- `handle_delete/2` stops the pipeline.

The pipeline cross-links two `Membrane.UDP.Endpoint`s, so whatever one peer
sends goes out to the other, and records each direction's raw RTP payload to
`docker/recordings/<call_id>__<from>_to_<to>.raw` as proof that the audio went
through Membrane. Codecs are whatever the peers negotiate; the e2e call uses
G.711 A-law, which plays with:

    ffplay -f alaw -ar 8000 -ac 1 docker/recordings/<call_id>__offerer_to_answerer.raw

## Running it

Everything runs in Docker on the host network (with Colima on macOS; Docker
Desktop needs host networking enabled in its settings):

    cd docker
    ./e2e.sh

This builds Kamailio with the library's `kamailio.cfg`, the relay, and a SIPp
UAS registered as `1000` that echoes RTP back; then it places one call with
SIPp playing `g711a.pcap` and checks that both recordings contain exactly the
pcap's payload.

To use softphones, start the stack with the address they can reach the docker
host at (with Colima: `colima status` shows it):

    ADVERTISE_IP=192.168.64.2 docker compose up -d --build

Register two accounts there (UDP, any password, media encryption off) and call
each other, or dial `1000` to hear yourself echoed back through the relay. For a
phone outside your network, run Tailscale on the docker host (the
`tailscale/tailscale` image with `network_mode: host` will do) and use its
tailnet address.

## Limitations

- One audio stream per call; any other m-line is rejected with port 0.
- No NAT traversal: RTP goes to the address in each peer's SDP. Setting
  `latch?: true` on the endpoints in `RelayHandler.Pipeline` makes the relay
  follow the source of incoming packets instead.
