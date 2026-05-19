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

  # IP advertised in SDP `c=` lines — the address your box is reachable
  # at from the SIP peers.
  media_ip: System.get_env("MEDIA_IP", "127.0.0.1"),

  # Pool of UDP ports ex_kamailio will allocate for RTP/RTCP. RTP gets
  # an even port; RTCP is the next odd port.
  port_range: 11_000..40_000,

  # Your handler module — implements `ExKamailio.Handler`.
  handler: MyApp.KamailioHandler,

  # Optional: payload types this peer is willing to terminate. If
  # omitted, ex_kamailio echoes whatever the offer carried.
  allowed_pts: [0, 8, 101]
```

## Writing a handler

```elixir
defmodule MyApp.KamailioHandler do
  @behaviour ExKamailio.Handler

  alias ExKamailio.SDP

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def offer(session, state) do
    # session.caller_local — endpoint ex_kamailio allocated for us
    # session.caller_remote — what the caller advertised in SDP
    # session.offer_sdp — full %ExSDP{} struct

    :ok = MyApp.Pipeline.attach_caller(session.call_id, session.caller_local)

    answer = SDP.answer_sdp(
      to_string(session.caller_local.ip),
      session.caller_local.rtp_port,
      session.caller_local.rtcp_port,
      [0, 101],
      "sendrecv"
    )

    {:ok, answer, state}
  end

  @impl true
  def answer(session, state) do
    :ok = MyApp.Pipeline.attach_callee(session.call_id, session.callee_local)

    answer = SDP.answer_sdp(
      to_string(session.callee_local.ip),
      session.callee_local.rtp_port,
      session.callee_local.rtcp_port,
      [0, 101],
      "sendrecv"
    )

    {:ok, answer, state}
  end

  @impl true
  def delete(session, state) do
    :ok = MyApp.Pipeline.stop(session.call_id)
    {:ok, state}
  end
end
```

The library handles WebSocket plumbing, Bencode parsing, SDP parsing,
local port allocation, and session bookkeeping. Your handler decides
what to do with the media.

## Call flow

1. Caller (A) sends `INVITE` + SDP to Kamailio.
2. Kamailio forwards the SDP to `ex_kamailio` over the rtpengine
   WebSocket as an `offer` command.
3. `ex_kamailio` parses the SDP, allocates a local RTP/RTCP port pair
   for the caller, and calls `c:ExKamailio.Handler.offer/2`.
4. Your handler returns an answer SDP. `ex_kamailio` sends it back to
   Kamailio, which puts it into the `INVITE` forwarded to callee (B).
5. Callee replies `200 OK` + SDP. Kamailio forwards as an `answer`
   command. `ex_kamailio` allocates a callee-side port and calls
   `c:ExKamailio.Handler.answer/2`.
6. Your handler returns an SDP for caller; `ex_kamailio` ships it back.
7. On call teardown, Kamailio sends `delete`, ex_kamailio calls
   `c:ExKamailio.Handler.delete/2`, and the ports return to the pool.

## NAT and dynamic IPs

Clients are typically behind NAT — the IPs in their SDPs are not the
addresses the RTP actually arrives from. The standard solution is
symmetric RTP (latching): you bind a UDP socket on the local port
ex_kamailio allocated for the peer, wait for the first inbound packet,
read the source IP/port from the headers, and from then on send to
that observed address.

ex_kamailio does the port allocation; the latching belongs in the
media component you run inside your handler (e.g.
`Membrane.UDP.Source`).

## Testing

Two paths, increasing in cost:

1. **Smoke test, no Kamailio needed.** Run
   `mix kamailio.smoke` from inside `examples/echo_handler`. It
   boots ex_kamailio and connects to it over a real WebSocket on
   loopback, replaying a realistic offer/answer/delete sequence.
2. **Full SIP path with real Kamailio.** Drive Kamailio (configured
   with `rtpengine` + `lwsc` modules pointing at ex_kamailio) from
   SIPp UAC + UAS. See `examples/echo_handler/README.md` for the
   step-by-step setup, including a working `kamailio.cfg`.

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
