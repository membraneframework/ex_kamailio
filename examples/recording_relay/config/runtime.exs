import Config

# The address both peers reach the relay at; it goes into every SDP returned.
{:ok, media_ip} =
  System.get_env("ADVERTISE_IP", "127.0.0.1")
  |> String.to_charlist()
  |> :inet.parse_address()

# Each call takes a free consecutive pair from this range; docker/compose.yml publishes it.
config :recording_relay,
  media_ip: media_ip,
  rtp_ports: 10000..10099,
  recordings_dir: System.get_env("RECORDINGS_DIR", "recordings")
