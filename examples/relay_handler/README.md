# relay_handler

An `ExKamailio.CallHandler` that relays RTP between the two peers of a call
through a Membrane pipeline. ex_kamailio only shuttles SDP between Kamailio and
your code; the media is the handler's job. This one does the minimum:

- `init/2` starts one `RelayHandler.Pipeline` per call.
- `handle_offer/3` binds a UDP socket per peer and returns the offer with the
  relay's address and port in place of the offerer's.
- `handle_answer/3` points the answerer-facing socket at the answerer and
  returns the answer rewritten the same way.
- `handle_delete/2` stops the pipeline.

The pipeline cross-links two `Membrane.UDP.Endpoint`s, so whatever one peer
sends goes out to the other, and records each direction's raw RTP payload to
`docker/recordings/<call_id>__<from>_to_<to>.raw` as proof that the audio went
through Membrane. The handler lets only G.711 A-law through, so every
recording plays with:

    ffplay -f alaw -ar 8000 -ac 1 docker/recordings/<call_id>__offerer_to_answerer.raw

## Running it

You need Docker with Compose v2, and ffplay (from ffmpeg) to listen to the
recordings. The stack is Kamailio with the library's `kamailio.cfg`, the relay
and a SIPp UAS registered as `1000` that echoes back whatever RTP it receives,
all on the host network. `ADVERTISE_IP` is the address the peers reach the
stack at; unset, it is `127.0.0.1`.

### Linux

`e2e.sh` builds the images, places one call with SIPp playing `g711a.pcap`,
and checks that both recordings contain exactly the pcap's payload:

    cd docker
    ./e2e.sh

For softphones, start the stack with the machine's LAN address instead and
register them there:

    ADVERTISE_IP=192.168.1.10 docker compose up -d --build

### macOS

Docker runs in a Linux VM here, so the host network is the VM's. `./e2e.sh`
works as on Linux (with Docker Desktop, enable host networking in its
settings first).

Softphones on the Mac reach the VM if Colima was started with
`--network-address`, at the address `colima status` shows:

    ADVERTISE_IP=192.168.64.2 docker compose up -d --build

Other devices cannot reach the VM at all, and with Docker Desktop neither can
the Mac, so for a phone put the stack on a tailnet:

    docker compose --profile tailscale up -d tailscale
    docker compose logs tailscale   # log in with the URL it prints
    ADVERTISE_IP=$(docker compose exec tailscale tailscale ip -4) docker compose up -d --build

Log the phone into the same tailnet, and the Mac too if it runs a softphone.

### Softphones

In Linphone, add a third-party SIP account with:

- username and password: anything, the Kamailio config checks no passwords
- domain: the `ADVERTISE_IP` above
- transport: UDP
- media encryption: none (Settings → Call)

Call another account, or `1000` to hear yourself echoed back through the
relay.

### Changing the handler

The relay runs from the image, so after editing `lib/` rebuild it with
`docker compose up -d --build relay`. For a quick check without Docker,
`mix deps.get && mix compile`.

## Limitations

- Nothing is hardened: Kamailio accepts any REGISTER and the relay forwards
  whatever it gets. Keep the stack on a private network.
- One audio stream per call; any other m-line is rejected with port 0.
- G.711 A-law only; a peer offering nothing else gets an empty codec list.
- Peers behind NAT get their audio once they have sent some: the relay sends
  to the address from the SDP until packets arrive, then to wherever they come
  from. Nothing checks who sends them.
