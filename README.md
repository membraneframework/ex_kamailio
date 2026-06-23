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
Membrane itself. You implement the `ExKamailio.CallHandler` behaviour and
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

  # Your handler module — implements `ExKamailio.CallHandler`. Use
  # {module, opts} to pass options to its init/1.
  call_handler: MyApp.KamailioHandler
```

ex_kamailio is a pure SDP shuttle: it owns no media ports and picks no
codecs. Your handler binds its own sockets and advertises them in the SDP it
returns. The advertised IP is the handler's choice too — your handler can,
for instance, auto-detect this host's first non-loopback IPv4.

## Writing a handler

```elixir
defmodule MyApp.KamailioHandler do
  use ExKamailio.CallHandler

  @impl true
  def init(_opts), do: {:ok, %{pipeline: nil}}

  @impl true
  def handle_offer(offer, session, state) do
    {:ok, reply_sdp, pid} = MyApp.Media.open(session.call_id, offer)
    {:ok, reply_sdp, %{state | pipeline: pid}}
  end

  @impl true
  def handle_answer(answer, _session, state) do
    {:ok, reply_sdp} = MyApp.Media.add_answerer(state.pipeline, answer)
    {:ok, reply_sdp, state}
  end

  @impl true
  def handle_delete(_session, state) do
    MyApp.Media.stop(state.pipeline)
    {:ok, state}
  end
end
```

The callbacks receive the peer's parsed offer/answer (`%ExSDP{}`) and return the
`%ExSDP{}` to advertise back — pointed at the media socket your code bound. The
library handles WebSocket plumbing, Bencode parsing, SDP parsing, and per-call
session bookkeeping; your handler owns the media and the SDP it returns.

`state` is kept **per call** (keyed by `session.call_id`): `init/1` seeds each
new call, your callbacks receive and return that call's state, and it is dropped
on `handle_delete/2` — so keeping a pipeline pid in a bare field, as above, is safe even
with many overlapping calls.

## Call flow

The peers are named by their RFC 3264 roles — **offerer** proposes SDP,
**answerer** responds. In the initial `INVITE` (all ex_kamailio implements
so far) the offerer is the caller.

1. The offerer (A) sends `INVITE` + SDP to Kamailio.
2. Kamailio forwards the SDP to `ex_kamailio` over the rtpengine
   WebSocket as an `offer` command.
3. `ex_kamailio` parses the SDP and calls `c:ExKamailio.CallHandler.handle_offer/3`.
   Your handler binds its media socket and returns an SDP advertising it.
4. `ex_kamailio` sends that SDP back to Kamailio, which puts it into the
   `INVITE` forwarded to the answerer (B) — it is the offer B sees.
5. B replies `200 OK` + SDP. Kamailio forwards it as an `answer`
   command and `ex_kamailio` calls `c:ExKamailio.CallHandler.handle_answer/3`.
6. Your handler returns the SDP that goes back to A as the answer in
   the forwarded `200 OK`.
7. On call teardown, Kamailio sends `delete`, ex_kamailio calls
   `c:ExKamailio.CallHandler.handle_delete/2`, and your handler releases whatever it
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

The library's own suite drives the `ExKamailio.WebSocket` handler and the
per-call server directly, with no Kamailio required:

    mix test

For a full SIP path, point a real Kamailio at the library-provided reference
config (`priv/kamailio/kamailio.cfg`, which wires up the `rtpengine` + `lwsc`
modules to ex_kamailio) and drive it with a SIP test tool such as SIPp.

## Status

Early alpha. Implements `offer` / `answer` / `delete` / `ping`. Not
yet covered: `update`, `query`, ICE, DTLS, transcoding-related
extensions.

## Acknowledgements

Originally extracted from a Kamailio integration written by
**Javier Gallart (BTS)**, who graciously permitted relicensing the
relevant parts as open source.

## License

MIT — see [LICENSE](LICENSE). Portions derive from the ex_media project by
Javier Gallart / BTS, used with permission.

[kamailio]: https://www.kamailio.org/
[membrane]: https://membrane.stream/
