FROM elixir:1.17-otp-27-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN mix local.hex --force && mix local.rebar --force

WORKDIR /src/examples/recording_relay
ENV MIX_ENV=prod

# ex_kamailio is a path dependency, so deps.get needs its mix.exs too.
COPY mix.exs /src/
COPY examples/recording_relay/mix.exs examples/recording_relay/mix.lock ./
RUN mix deps.get

COPY lib /src/lib
COPY examples/recording_relay/config/config.exs config/
COPY examples/recording_relay/lib lib
RUN mix compile

COPY examples/recording_relay/config/runtime.exs config/

CMD ["mix", "run", "--no-halt"]
