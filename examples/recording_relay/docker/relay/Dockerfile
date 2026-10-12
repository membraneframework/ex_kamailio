FROM elixir:1.17-otp-27-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY mix.exs mix.lock ./
COPY lib ./lib
COPY examples/recording_relay/mix.exs examples/recording_relay/mix.lock ./examples/recording_relay/
COPY examples/recording_relay/config ./examples/recording_relay/config
COPY examples/recording_relay/lib ./examples/recording_relay/lib

WORKDIR /src/examples/recording_relay
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force && mix deps.get && mix compile

CMD ["mix", "run", "--no-halt"]
