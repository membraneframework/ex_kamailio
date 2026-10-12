FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends kamailio kamailio-lwsc-modules \
    && rm -rf /var/lib/apt/lists/*

# PUBLIC_MODE makes the cfg advertise ADVERTISE_IP instead of 0.0.0.0.
CMD ["kamailio", "-f", "/etc/kamailio/kamailio.cfg", "-DD", "-E", "-A", "PUBLIC_MODE"]
