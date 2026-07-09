import Config

config :ex_kamailio, ws_port: 4003

if config_env() == :test, do: import_config("test.exs")
