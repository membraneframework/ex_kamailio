# ex_kamailio

Elixir integration for the [Kamailio][kamailio] SIP server.

`ex_kamailio` speaks the rtpengine `ng` control protocol over a WebSocket, so
a Kamailio routing script can hand media setup to an Elixir application.

## Why

Kamailio does the SIP signaling and leaves the media to rtpengine. With
`ex_kamailio` an Elixir application takes rtpengine's place: one behaviour,
called with each call's SDP, decides where the media goes.

It was written to put a [Membrane][membrane] pipeline between two SIP peers,
but it neither depends on Membrane nor assumes it.

## Installation

Add `ex_kamailio` to your dependencies:

```elixir
def deps do
  [
    {:ex_kamailio, "~> 0.1.0"}
  ]
end
```

## Writing a call handler

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
    :ok
  end
end
```

The callbacks get the peer's SDP as `%ExSDP{}` and return the `%ExSDP{}` to
send on. Each call runs in its own process, with its own state.

## Configuration

```elixir
config :ex_kamailio,
  # Your `ExKamailio.CallHandler` module, or `{module, opts}`. Default:
  # `ExKamailio.CallHandler.Default`, which returns each peer's SDP unchanged.
  call_handler: MyApp.KamailioHandler,

  # Where the WebSocket server listens for Kamailio. Defaults: loopback, 4003.
  ws_ip: :loopback,
  ws_port: 4003,

  # Idle time before `handle_idle/2` fires. Default: 30 min.
  idle_timeout: :timer.minutes(30),

  # Per-callback deadline; keep under Kamailio's `rtpengine_tout_ms`. Default: 800 ms.
  callback_timeout: 800
```

The WebSocket is plain `ws`, no TLS. When Kamailio runs on another host or in
another container, set `ws_ip` to an address it can reach, `{0, 0, 0, 0}`
binds every interface, and keep the port off the public internet.

## Call flow

Peers are named by their RFC 3264 roles: the **offerer** proposes SDP, the
**answerer** responds. In the initial `INVITE` the offerer is the caller.

1. The offerer sends `INVITE` with SDP. Kamailio passes the SDP to
   `ex_kamailio` as an `offer` command. `ex_kamailio` starts a call process and
   calls `c:ExKamailio.CallHandler.handle_offer/3`; the SDP it returns goes
   into the `INVITE` forwarded to the answerer.
2. The answerer replies `200 OK` with SDP. Kamailio passes it as an `answer`
   command, and the SDP `c:ExKamailio.CallHandler.handle_answer/3` returns goes
   into the `200 OK` forwarded to the offerer.
3. On `BYE`, Kamailio sends `delete` and
   `c:ExKamailio.CallHandler.handle_delete/2` releases what the handler
   allocated. A cancelled or rejected `INVITE` sends nothing; that call ends
   by the idle timeout below.

## Idle calls

When `delete` never comes, because a peer crashed or a `BYE` got lost, the
call process would live forever. So when no command arrives for
`:idle_timeout` (default 30 min), `c:ExKamailio.CallHandler.handle_idle/2`
runs. Its default returns `{:stop, state}`, which runs `handle_delete/2` and
stops the process; return `{:ok, state}` to keep the call.

This only frees the process. The SIP dialog goes on, and both peers may keep
sending and expecting media.

## Kamailio config

`priv/kamailio/kamailio.cfg` is a minimal config that wires the `rtpengine`
and `lwsc` modules to `ex_kamailio`: a registrar with no authentication and a
proxy that puts every call to a registered user through the handler.
Copy it and extend it when it stops being enough; its header lists what a
real deployment would add.

It reads two environment variables:

- `RTPENGINE_SOCK`: where `ex_kamailio` listens, as a WebSocket URL.
  `ws://127.0.0.1:4003` when Kamailio shares the host's network,
  `ws://<name>:4003` when it reaches the app by DNS, e.g. a Docker service
  name.
- `ADVERTISE_IP`: the address peers reach Kamailio at. Used only with
  `-A PUBLIC_MODE`.

By default Kamailio binds `0.0.0.0:5060` and advertises that, which breaks
in-dialog requests (`BYE`, `ACK`) as soon as the peers are on other hosts.
Start it with `-A PUBLIC_MODE` to advertise `ADVERTISE_IP` instead.

## Status

Implements the `offer`, `answer`, `delete` and `ping` rtpengine commands.
`update` and `query` are not covered yet.

## License

MIT. See [LICENSE](LICENSE). Portions derive from the ex_media project by
Javier Gallart / BTS, used with permission.

## Authors

`ex_kamailio` is created by Software Mansion.

Since 2012 [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=ex_kamailio) is a software agency with experience in building web and mobile apps as well as complex multimedia solutions. We are Core React Native Contributors and experts in live streaming and broadcasting technologies. We can help you build your next dream product – [Hire us](https://swmansion.com/contact/projects).

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=ex_kamailio-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=ex_kamailio)

`ex_kamailio` was originally extracted from a Kamailio integration written by
**Javier Gallart (BTS)**, who graciously permitted relicensing the relevant
parts as open source.

[kamailio]: https://www.kamailio.org/
[membrane]: https://membrane.stream/
