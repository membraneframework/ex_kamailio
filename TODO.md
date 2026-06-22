# ex_kamailio — deferred work

Things deliberately put off. None block current functionality.

## Before any Hex release

- **Tag `v0.1.0`** on the published commit (`mix.exs` `source_ref` points
  HexDocs at `blob/v0.1.0/...`): `git tag v0.1.0 && git push origin v0.1.0`.

## Reference `kamailio.cfg` (`priv/kamailio/kamailio.cfg`)

Lifted from the demo; to generalize:

- Parameterize via env vars: the rtpengine socket URL (`cfg:45-50`, the
  ex_kamailio integration point) and the advertise IP (`cfg:9-14`, currently
  `ADVERTISE_PLACEHOLDER` + compose-`sed`).
- Document the deliberate omissions: no REGISTER auth (open registrar),
  `usrloc db_mode=0` (in-memory), UDP-only, no signaling-NAT helper.

## Prompt teardown of crashed calls (rtpengine `--b2b-url` analogue)

A handler crash in `handle_info/3`/`handle_timeout/2` kills the call process
silently — the ng protocol is request/response, so Kamailio keeps the dialog up
with dead media until someone hangs up. Mirror rtpengine: load the `dialog`
module + `jsonrpcs`, and have ex_kamailio monitor call processes and POST
`dlg.terminate_dlg` (call-id + from/to tags) on abnormal exit.

## Roadmap

`update`/`query` commands, ICE, DTLS/SRTP, transcoding.
