import Config

config :ex_kamailio,
  ws_port: 4003,
  media_ip: System.get_env("MEDIA_IP", "127.0.0.1"),
  port_range: 11_000..40_000
