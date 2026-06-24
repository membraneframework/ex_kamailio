# ex_kamailio

Elixir integration for the [Kamailio][kamailio] SIP server.

`ex_kamailio` speaks Kamailio's `rtpengine` `ng` control protocol over a
WebSocket transport, so a Kamailio routing
script can delegate media setup to an Elixir application.

Kamailio handles SIP signaling; your Elixir code decides what happens to
the media.

## Why

Kamailio is widely deployed because few open-source alternatives can
handle high-volume SIP signaling efficiently. But integrating it with an
Elixir media stack normally requires a lot of glue. `ex_kamailio`
collapses that glue into one behaviour you implement.

One of the library's goals is to make it easy to integrate [Membrane][membrane]
into services built on SIP and Kamailio. The package carries no Membrane
dependency itself, but it's designed to make plugging a Membrane pipeline
between two peers as easy as possible. You can also use it in solutions that
don't involve Membrane at all — `ex_kamailio` never assumes it.

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

  # Your handler module that implements `ExKamailio.CallHandler`. Use
  # {module, opts} to pass options to its init/2.
  call_handler: MyApp.KamailioHandler
```

`ex_kamailio` is a pure SDP shuttle: it owns no media ports and picks no
codecs. Your handler can bind its own sockets and advertise them in the 
SDP it returns. 

## Writing an `ExKamailio.CallHandler` implementation

```elixir
defmodule MyApp.KamailioHandler do
  use ExKamailio.CallHandler

  @impl true
  def init(_session, _opts), do: {:ok, %{pipeline: nil}}

  @impl true
  def handle_offer(offer, session, state) do
    {:ok, reply_sdp, pid} = MyApp.MediaPipeline.start_link(session.call_id, offer)
    {:ok, reply_sdp, %{state | pipeline: pid}}
  end

  @impl true
  def handle_answer(answer, _session, state) do
    {:ok, reply_sdp} = MyApp.MediaPipeline.add_answerer(state.pipeline, answer)
    {:ok, reply_sdp, state}
  end

  @impl true
  def handle_delete(_session, state) do
    MyApp.MediaPipeline.terminate(state.pipeline)
    {:ok, state}
  end
end
```

The callbacks receive the peer's parsed offer/answer (`%ExSDP{}`) and return the
`%ExSDP{}` to advertise back. Each Kamailio dialog gets its own
`ExKamailio.CallHandler` process with separate state.

## Call flow

The peers are named by their RFC 3264 roles: **offerer** proposes SDP,
**answerer** responds. In the initial `INVITE` the offerer is the caller.

1. The offerer (Peer A) sends `INVITE` + SDP to Kamailio.
2. Kamailio forwards the SDP to `ex_kamailio` over the rtpengine
   WebSocket as an `offer` command.
3. `ex_kamailio` parses the SDP, spawns a new call handler, and calls
   `c:ExKamailio.CallHandler.handle_offer/3`. Your implementation returns an
   `%ExSDP{}` struct — the SDP offer for the answerer (Peer B).
4. `ex_kamailio` sends that SDP back to Kamailio, which puts it into the
   `INVITE` forwarded to the answerer.
5. Peer B replies `200 OK` + SDP. Kamailio forwards it as an `answer`
   command and `ex_kamailio` calls `c:ExKamailio.CallHandler.handle_answer/3`.
6. Your call handler returns the SDP that goes back to Peer A as the answer
   in the forwarded `200 OK`.
7. On call teardown, Kamailio sends `delete`, `ex_kamailio` calls
   `c:ExKamailio.CallHandler.handle_delete/2`, and your handler releases whatever it
   allocated.

## Idle calls

A call normally ends when Kamailio sends `delete`. Should that never arrive —
a crashed peer, a lost `BYE` — the call process would otherwise linger forever.
To guard against this, each call runs an idle timer: when no command arrives
for `:idle_timeout` (default 30 min), `c:ExKamailio.CallHandler.handle_idle/2`
fires. Its default returns `{:stop, state}`, which runs `handle_delete/2` and
then stops the process; override it to return `{:ok, state}` to keep the call
alive instead.

Note that reaping is local only: it frees the call process but does not end the
SIP dialog. Even after the call handler is gone, both peers may keep sending and
expecting media.

## Kamailio config

The library ships a reference Kamailio config at `priv/kamailio/kamailio.cfg`,
which wires up the `rtpengine` + `lwsc` modules to `ex_kamailio`. Point a real
Kamailio at it to put the library on a full SIP path.

It works with `ex_kamailio` out of the box, but it won't cover every SIP
scenario you might run into. When it falls short, treat it as a starting
point, copy it into your project and tweak it (add modules, routing logic,
whatever you need) as you go.

It takes its connection details from the environment:

- `RTPENGINE_SOCK` — the `ng` control socket of your `ex_kamailio` app, as a
  WebSocket URL. Use `ws://127.0.0.1:4003` when Kamailio shares the host's
  network (loopback), or `ws://<name>:4003` when it reaches the app by DNS
  (e.g. a Docker service name).
- `ADVERTISE_IP` — the address peers use to reach Kamailio. Only consulted in
  LAN mode (below); leave it unset otherwise.

By default Kamailio binds UDP `0.0.0.0:5060` and advertises that bind address.
That breaks once peers aren't on the same host, because in-dialog requests
(BYE/ACK) get pointed back at `0.0.0.0`. Start Kamailio with `-A LAN_MODE` to
instead advertise `ADVERTISE_IP`, the routable address you set above.

## Status

Implements the `offer` / `answer` / `delete` / `ping` rtpengine
commands; `update` and `query` are not yet covered.

## Acknowledgements

Originally extracted from a Kamailio integration written by
**Javier Gallart (BTS)**, who graciously permitted relicensing the
relevant parts as open source.

## License

MIT — see [LICENSE](LICENSE). Portions derive from the ex_media project by
Javier Gallart / BTS, used with permission.

[kamailio]: https://www.kamailio.org/
[membrane]: https://membrane.stream/
