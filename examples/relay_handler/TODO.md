# relay_handler TODO

## API mismatches with current ex_kamailio
- [x] `init/1` -> `init/2`
- [x] `handle_delete` returns `:ok`
- [x] `LAN_MODE` -> `PUBLIC_MODE` (compose.lan.yml, READMEs)
- [x] `ws_ip` for bridge mode (`WS_IP=any`); drop redundant `ws_port: 4003`

## Bridge-mode e2e rig (found 2026-10-07; media bypassed the relay after 7.5 s since May)
- [x] `uac.xml`: ACK/BYE Request-URI was the proxy, not `[next_url]`; Kamailio took the strict-router
      path and relayed them to itself, so the UAS never got ACK, kept retransmitting 200 OK, and the
      retransmit after tm's wait timer carried the raw SDP, re-targeting the UAC's RTP at the sink
- [x] `compose.yml`: run Kamailio in `PUBLIC_MODE` with the container IP (Record-Route was `sip:0.0.0.0`)
- [ ] First 1-2 RTP packets lost: `handle_answer` replies before the new leg's socket is bound
      (bind both ports at offer, or wait for the pipeline to confirm the leg)
- [ ] Fixture is PCMA (PT 8) but the relay forces/decodes PCMU: relay WAVs are garbled in bridge mode
      (`gen_tone_pcap.sh`: `-f mulaw`, PT 0x00)
- [ ] Automated check: relay-forwarded packet count == sink packet count, sink bytes == fixture bytes
      (SIPp's own "Successful call" is unreliable: it matched a 200 OK retransmit as the BYE reply)

## Stale docs
- [ ] `docker/compose.yml`: "`auto` makes ex_kamailio detect" comment
- [ ] README says codecs are negotiated by peers, but the example forces PCMU
- [ ] Trim `docker/README.md` (372 lines)
- [ ] Callback docs in READMEs/moduledocs match current API
- [ ] `docker/README.md`: both modes now use `PUBLIC_MODE`; LAN overlay no longer overrides the command

## To decide
- [ ] Symmetric-RTP latching (dropped with one-way legs; NAT'd peers don't work)
- [ ] Port advertised at offer is bound one-way only until answer
- [ ] RTCP not relayed

## General
- [ ] Review the example code
- [ ] Link the example from the library README (removed in 1fecb42)
- [ ] Live tests: `mix kamailio.smoke`, docker + SIPp (bridge), softphones (LAN, Tailscale)
