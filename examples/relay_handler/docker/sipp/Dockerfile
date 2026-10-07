FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends sip-tester \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /scenarios
