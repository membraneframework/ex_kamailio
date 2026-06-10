# ex_kamailio

Elixir integration for the [Kamailio][kamailio] SIP server.

`ex_kamailio` speaks Kamailio's `rtpengine` `ng` control protocol over a
WebSocket transport (Bencode-encoded payloads), so a Kamailio routing
script can delegate media setup to an Elixir application — typically one
running a [Membrane][membrane] pipeline on the receiving end.

Kamailio handles SIP signaling; your Elixir code decides what happens to
the media.

## Why

Kamailio is widely deployed because few open-source alternatives can
handle high-volume SIP signaling efficiently. But integrating it with an
Elixir media stack normally requires a lot of glue. `ex_kamailio`
collapses that glue into one behaviour you implement.

The library deliberately stays Membrane-free — it has no dependency on
Membrane itself. You implement the `ExKamailio.Handler` behaviour and
decide what to do with the media (Membrane pipeline, FFmpeg subprocess,
log-only, etc.).

## Installation

Add `ex_kamailio` to your dependencies:

```elixir
def deps do
  [
    {:ex_kamailio, "~> 0.1.0"}
  ]
end
```

## Configuration

```elixir
config :ex_kamailio,
  # TCP port the embedded Bandit server listens on for Kamailio's
  # rtpengine WebSocket connection.
  ws_port: 4003,

  # Your handler module — implements `ExKamailio.Handler`.
  handler: MyApp.KamailioHandler
```

ex_kamailio is a pure SDP shuttle: it owns no media ports and picks no
codecs. Your handler binds its own sockets and advertises them in the SDP it
returns. The advertised IP is the handler's choice too — see how the
relay_handler example auto-detects this host's first non-loopback IPv4.

## Writing a handler

```elixir
defmodule MyApp.KamailioHandler do
  use ExKamailio.Handler

  alias ExKamailio.SDP

  @impl true
  def init(_opts), do: {:ok, %{pipeline: nil}}

  @impl true
  def offer(session, state) do
    # session.caller_remote — what the caller advertised in SDP (parsed for you)
    # session.offer_sdp     — full %ExSDP{} struct

    # You own the media: bind your own socket / start a pipeline leg, then
    # advertise the endpoint you bound. `local` is an `%ExKamailio.Endpoint{}`
    # (ip + rtp_port) you choose.
    {:ok, local, pid} = MyApp.Media.open(session.call_id, session.caller_remote)

    # Forward the caller's SDP, repointed at your local endpoint. The peer's
    # codecs are preserved — ex_kamailio doesn't pick codecs for you.
    answer = SDP.rewrite_endpoint(session.offer_sdp, local)

    {:ok, answer, %{state | pipeline: pid}}
  end

  @impl true
  def answer(session, state) do
    {:ok, local} = MyApp.Media.add_callee(state.pipeline, session.callee_remote)
    answer = SDP.rewrite_endpoint(session.answer_sdp, local)
    {:ok, answer, state}
  end

  @impl true
  def delete(_session, state) do
    MyApp.Media.stop(state.pipeline)
    {:ok, state}
  end
end
```

The library handles WebSocket plumbing, Bencode parsing, SDP parsing, and
per-call session bookkeeping. Your handler owns the media — it binds its own
sockets / allocates its own ports and decides what to do with the stream.

`state` is kept **per call** (keyed by `session.call_id`): `init/1` seeds each
new call, your callbacks receive and return that call's state, and it is dropped
on `delete/2` — so keeping a pipeline pid in a bare field, as above, is safe even
with many overlapping calls.

Callbacks return an `%ExSDP{}` struct (build it with
`SDP.rewrite_endpoint/2`); a raw SDP string is also accepted.

## Call flow

1. Caller (A) sends `INVITE` + SDP to Kamailio.
2. Kamailio forwards the SDP to `ex_kamailio` over the rtpengine
   WebSocket as an `offer` command.
3. `ex_kamailio` parses the SDP and calls `c:ExKamailio.Handler.offer/2`.
   Your handler binds its media socket and returns an answer SDP
   advertising it.
4. `ex_kamailio` sends that SDP back to Kamailio, which puts it into the
   `INVITE` forwarded to callee (B).
5. Callee replies `200 OK` + SDP. Kamailio forwards as an `answer`
   command and `ex_kamailio` calls `c:ExKamailio.Handler.answer/2`.
6. Your handler returns an SDP for caller; `ex_kamailio` ships it back.
7. On call teardown, Kamailio sends `delete`, ex_kamailio calls
   `c:ExKamailio.Handler.delete/2`, and your handler releases whatever it
   allocated.

## NAT and dynamic IPs

Clients are typically behind NAT — the IPs in their SDPs are not the
addresses the RTP actually arrives from. The standard solution is
symmetric RTP (latching): bind a UDP socket on the local port you
advertised, wait for the first inbound packet, read the source IP/port
from the headers, and from then on send to that observed address.

Both the port and the latching belong in the media component you run
inside your handler (e.g. `Membrane.UDP.Source`); `ex_kamailio` is not
involved in the media path at all.

## Testing

Two paths, increasing in cost:

1. **Smoke test, no Kamailio needed.** Run
   `mix kamailio.smoke` from inside `examples/relay_handler`. It
   boots ex_kamailio and connects to it over a real WebSocket on
   loopback, replaying a realistic offer/answer/delete sequence.
2. **Full SIP path with real Kamailio.** Drive Kamailio with the
   library-provided reference config (`priv/kamailio/kamailio.cfg`,
   which wires up the `rtpengine` + `lwsc` modules pointing at
   ex_kamailio) from SIPp UAC + UAS. See
   `examples/relay_handler/docker/README.md` for the step-by-step setup.

## Status

Early alpha. Implements `offer` / `answer` / `delete` / `ping`. Not
yet covered: `update`, `query`, ICE, DTLS, transcoding-related
extensions.

## Acknowledgements

Originally extracted from a Kamailio integration written by
**Javier Gallart (BTS)**, who graciously permitted relicensing the
relevant parts as open source.

## License

Apache-2.0.

[kamailio]: https://www.kamailio.org/
[membrane]: https://membrane.stream/
