FROM debian:bookworm-slim

# `kamailio` ships rtpengine.so; the lwsc (lightweight WebSocket client)
# module is shipped separately and lets the rtpengine module talk to a
# ws:// control socket instead of the default UDP transport.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        kamailio \
        kamailio-lwsc-modules \
    && rm -rf /var/lib/apt/lists/*

# kamailio.cfg is not baked in — compose.yml bind-mounts the library's
# priv/kamailio/kamailio.cfg at /etc/kamailio/kamailio.cfg.

EXPOSE 5060/udp

# -DD keeps Kamailio in the foreground with debug logging on stderr —
# easier to watch from `docker compose logs`.
CMD ["kamailio", "-f", "/etc/kamailio/kamailio.cfg", "-DD", "-E"]
