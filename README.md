# ExMedia

An Elixir-based RTP engine implementation supporting both UDP and WebSocket protocols.

## Features

- UDP and WebSocket protocol support
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
config :ex_media, :rtpengine_instances, [
  %{
    protocol: :udp,
    name: :rtp_udp,
    options: [port: 22222]
  },
  %{
    protocol: :websocket,
    name: :rtp_ws,
    options: [port: 8080]
  }
]
```

## Usage

### UDP Protocol

Send commands using UDP with bencode encoding:

```elixir
# Offer command
command = %{
  "command" => "offer",
  "sdp" => "v=0\no=- 123456 2 IN IP4 127.0.0.1\n..."
}
encoded = ExBencode.encode(command)
:gen_udp.send(socket, {127, 0, 0, 1}, 22222, encoded)
```

### WebSocket Protocol

Connect to the WebSocket endpoint and send JSON commands:

```elixir
# Offer command
command = %{
  "command" => "offer",
  "sdp" => "v=0\no=- 123456 2 IN IP4 127.0.0.1\n..."
}
# Send as JSON string
websocket.send(Jason.encode!(command))
```

## License

MIT

