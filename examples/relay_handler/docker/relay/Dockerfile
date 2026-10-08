FROM elixir:1.17-otp-27-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# The example depends on the library by path, so the image needs both;
# the build context is the repo root.
WORKDIR /src
COPY mix.exs mix.lock ./
COPY lib ./lib
COPY examples/relay_handler/mix.exs examples/relay_handler/mix.lock ./examples/relay_handler/
COPY examples/relay_handler/config ./examples/relay_handler/config
COPY examples/relay_handler/lib ./examples/relay_handler/lib

WORKDIR /src/examples/relay_handler
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force && mix deps.get && mix compile

CMD ["mix", "run", "--no-halt"]
