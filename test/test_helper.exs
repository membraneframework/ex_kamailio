ExUnit.start()

# Stop the application so tests start Registry/CallSupervisor themselves and
# Bandit doesn't hold the WS port.
Application.stop(:ex_kamailio)
