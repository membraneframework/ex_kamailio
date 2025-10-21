# config/config.exs
import Config

config :ex_media,
  ws_port: 4003,
  # Advertised/local IP for SDP c= and a=rtcp. You can also detect at runtime.
  media_ip: System.get_env("MEDIA_IP", "192.168.36.76"),
  # Inclusive port range (will allocate even base for RTP, odd for RTCP)
  port_range: 11000..40000

config :shine_membrane_pipeline,
  streams_in_batch: System.get_env("MEMBRANE_STREAMS_IN_BATCH", "8") |> String.to_integer(),
  tick_time_ms: System.get_env("MEMBRANE_TICK_TIME_MS", "10") |> String.to_integer(),
  latency_tick_count: System.get_env("MEMBRANE_LATENCY_TICK_COUNT", "6") |> String.to_integer()
