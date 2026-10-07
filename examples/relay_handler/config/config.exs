import Config

config :ex_kamailio, call_handler: RelayHandler

# The address both peers reach the relay at; it goes into every SDP returned.
{:ok, media_ip} =
  :inet.parse_address(String.to_charlist(System.get_env("ADVERTISE_IP", "127.0.0.1")))

config :relay_handler,
  media_ip: media_ip,
  recordings_dir: System.get_env("RECORDINGS_DIR", "recordings")
