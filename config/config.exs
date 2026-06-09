import Config

config :ex_kamailio, ws_port: 4003

# Tests drive WebSocket.handle_in/2 directly, so let the OS pick an ephemeral
# port for the embedded Bandit server instead of colliding on 4003.
if config_env() == :test, do: config(:ex_kamailio, ws_port: 0)
