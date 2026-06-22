# ex_kamailio — deferred work

Things deliberately put off. None block current functionality.

## Before any Hex release

- **Tag `v0.1.0`** on the published commit (`mix.exs` `source_ref` points
  HexDocs at `blob/v0.1.0/...`): `git tag v0.1.0 && git push origin v0.1.0`.

## Reference `kamailio.cfg` (`priv/kamailio/kamailio.cfg`)

Lifted from the demo; to generalize:

- Document the deliberate omissions: no REGISTER auth (open registrar),
  `usrloc db_mode=0` (in-memory), UDP-only, no signaling-NAT helper.

## Roadmap

`update`/`query` commands, ICE, DTLS/SRTP, transcoding.
