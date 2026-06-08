ExUnit.start()

# Stop the application so tests can own the GenServer lifecycle (port pool /
# session table need to be re-initialized with test-specific config, and we
# don't want Bandit binding the production WS port during tests).
Application.stop(:ex_kamailio)
