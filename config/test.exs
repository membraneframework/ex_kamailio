import Config

# Bind the WebSocket server to an OS-assigned free port so tests don't clash.
config :ex_kamailio, ws_port: 0
