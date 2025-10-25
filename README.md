# ExMedia

An Elixir-based rtpengine emulator, supporting WebSocket protocol.

## Features

- WebSocket protocol support
- Dynamic port allocation (10000-65000)
- Command handling for offer/answer/delete operations
- Worker process management for RTP sessions
- SDP parsing and transformation

## Installation

Add `ex_media` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_media, "~> 0.1.0"}
  ]
end
```

## Configuration

Configure RTP engine instances in your config:

```elixir
config :ex_media, 
  ws_port: 4003,
  # Advertised/local IP for SDP c= and a=rtcp. You can also detect at runtime.
  media_ip: System.get_env("MEDIA_IP", "192.168.36.76"),
  # Inclusive port range (will allocate even base for RTP, odd for RTCP)
  port_range: 11000..40000
```

## License

MIT

