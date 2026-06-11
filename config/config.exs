import Config

# rtpengine_command_timeout must stay under Kamailio's rtpengine_tout_ms (default 1000 ms).
config :ex_kamailio, ws_port: 4003, call_timeout: :timer.minutes(30), rtpengine_command_timeout: 800

# Tests drive WebSocket.handle_in/2 directly, so let the OS pick an ephemeral
# port for the embedded Bandit server instead of colliding on 4003.
if config_env() == :test, do: config(:ex_kamailio, ws_port: 0)
