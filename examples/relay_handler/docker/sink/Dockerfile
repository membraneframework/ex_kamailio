# Small Membrane-based UDP sink: binds a port, parses RTP, writes the
# depayloaded payload bytes to a file. Stands in for the receiving peer
# in the relay_handler E2E rig so the user can listen to what crossed
# the relay (`ffplay -f alaw -ar 8000 -ac 1 recordings/uas.alaw`).

FROM elixir:1.17-otp-27-slim AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY mix.exs ./
COPY lib ./lib

RUN mix local.hex --force && mix local.rebar --force \
    && MIX_ENV=prod mix deps.get \
    && MIX_ENV=prod mix compile

ENV MIX_ENV=prod

EXPOSE 6000/udp

CMD ["mix", "run", "--no-halt"]
