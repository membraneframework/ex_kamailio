import Config

config :ex_kamailio,
  ws_port: 4003,
  idle_timeout: :timer.minutes(30),
  callback_timeout: 800

if config_env() == :test, do: import_config("test.exs")
