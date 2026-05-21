# Builds and runs the relay_handler example on the Colima docker network so
# that the Membrane pipeline can both receive RTP from sipp-uac/uas AND send
# RTP back to them. Running the relay on the macOS host doesn't work because
# the host can't route to container bridge IPs.
#
# Build context is `../../..` (the ex_kamailio package root). That way the
# library source and the relay_handler example both ship into the image.

FROM elixir:1.17-otp-27-slim AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Bring in the library and the example. mix.lock keeps deps reproducible.
COPY mix.exs mix.lock ./
COPY lib ./lib
COPY examples/relay_handler/mix.exs examples/relay_handler/mix.lock ./examples/relay_handler/
COPY examples/relay_handler/config ./examples/relay_handler/config
COPY examples/relay_handler/lib ./examples/relay_handler/lib

WORKDIR /src/examples/relay_handler

RUN mix local.hex --force && mix local.rebar --force \
    && MIX_ENV=prod mix deps.get \
    && MIX_ENV=prod mix compile

ENV MIX_ENV=prod

EXPOSE 4003/tcp
# RTP port range — must match config.exs.
EXPOSE 11000-11200/udp

CMD ["mix", "run", "--no-halt"]
