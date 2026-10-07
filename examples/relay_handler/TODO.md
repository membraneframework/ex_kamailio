# relay_handler TODO

## API mismatches with current ex_kamailio
- [x] `init/1` -> `init/2`
- [x] `handle_delete` returns `:ok`
- [ ] `LAN_MODE` -> `PUBLIC_MODE` (compose.lan.yml, READMEs)
- [ ] `ws_ip: {0, 0, 0, 0}` for bridge mode; drop redundant `ws_port: 4003`

## Stale docs
- [ ] `docker/compose.yml`: "`auto` makes ex_kamailio detect" comment
- [ ] README says codecs are negotiated by peers, but the example forces PCMU
- [ ] Trim `docker/README.md` (372 lines)
- [ ] Callback docs in READMEs/moduledocs match current API

## To decide
- [ ] Symmetric-RTP latching (dropped with one-way legs; NAT'd peers don't work)
- [ ] Port advertised at offer is bound one-way only until answer
- [ ] RTCP not relayed

## General
- [ ] Review the example code
- [ ] Link the example from the library README (removed in 1fecb42)
- [ ] Live tests: `mix kamailio.smoke`, docker + SIPp (bridge), softphones (LAN, Tailscale)
