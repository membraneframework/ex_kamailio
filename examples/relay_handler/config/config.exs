import Config

config :ex_kamailio,
  ws_port: 4003,
  call_handler: RelayHandler

# The handler owns the media; these are the example's, not the library's.
# MEDIA_IP=auto (the default) advertises this host's first non-loopback IPv4 in
# SDP; set MEDIA_IP to a specific address to override.
config :relay_handler,
  media_ip: System.get_env("MEDIA_IP", "auto"),
  port_range: 11_000..40_000,
  # Where per-direction WAV recordings land. Docker sets RECORDINGS_DIR to the
  # bind-mounted /recordings; on the host it defaults to a local recordings/.
  recordings_dir: System.get_env("RECORDINGS_DIR", "recordings")
