# config/config.exs
import Config

config :ex_media,
  ws_port: 4001,
  # Advertised/local IP for SDP c= and a=rtcp. You can also detect at runtime.
  media_ip: System.get_env("MEDIA_IP", "192.168.36.76"),
  # Inclusive port range (will allocate even base for RTP, odd for RTCP)
  port_range: 10000..51000
