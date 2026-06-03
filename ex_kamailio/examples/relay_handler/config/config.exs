import Config

# MEDIA_IP=auto (the default) makes ex_kamailio advertise this host's first
# non-loopback IPv4 in SDP; set MEDIA_IP to a specific address to override.
config :ex_kamailio,
  ws_port: 4003,
  media_ip: System.get_env("MEDIA_IP", "auto"),
  port_range: 11_000..40_000,
  handler: RelayHandler
