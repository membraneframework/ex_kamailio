# ex_kamailio — deferred work

Running list of things we deliberately put off. Nothing here blocks current
functionality; it's a reminder so the decisions don't get lost.

## Before any Hex release

- **Tag `v0.1.0`.** `mix.exs` sets `docs: [source_ref: "v#{@version}"]`, but no
  git tag exists yet, so the "source" links in generated HexDocs will 404.

- **`source_url` / repo name.** The library now lives at the repo root, so
  `source_url` (`github.com/membraneframework-labs/ex_media`) resolves correctly
  and HexDocs source links no longer 404 on a subdir. Remaining mismatch: the
  repo is still named `ex_media` while the package is `ex_kamailio` — decide
  whether to rename the GitHub repo before publishing.

## Library-provided `kamailio.cfg` (`priv/kamailio/kamailio.cfg`)

The library now ships a reference config so users don't hand-roll one. It was
lifted as-is from the relay demo; two follow-ups make it a clean general-purpose
file rather than a demo artifact.

### Demo-specific → parameterize, don't rewrite

1. **rtpengine socket URL** (`cfg:45-50`) — hardcodes `ws://relay:4003` /
   `ws://127.0.0.1:4003` behind the `LAN_MODE` ifdef. This is *the* ex_kamailio
   integration point; in a library cfg it should read an env var (e.g.
   `#!substdef "!RTPENGINE_SOCK!ws://...!"` or `$env(EX_KAMAILIO_SOCK)`).
2. **Advertise IP** (`cfg:9-14`) — the `ADVERTISE_PLACEHOLDER` + compose-`sed`
   mechanism is demo glue. Kamailio can take this from an env var directly,
   dropping the sed entrypoint.
3. **`LAN_MODE` ifdef naming** — fine to keep, but for a shipped cfg frame it as
   "host-network vs. bridged" rather than the demo's tailnet story.

### Deliberately omitted → document, don't hide

For "usable beyond the demo," these are the gaps a user must know about:

- **No REGISTER auth** (`cfg:75-81`) — it's an open registrar; anyone can bind.
  Real use needs `auth`/`auth_db` digest. This is the big one to call out.
- **`usrloc db_mode=0`** (`cfg:37`) — in-memory, lost on restart. Fine for a
  demo/single-node; document `db_mode`/DB for persistence/HA.
- **UDP-only** (`cfg:13`) — no TCP/TLS listener; no WebSocket SIP transport.
- **SIP-signaling NAT** — media NAT is handled (rtpengine + the relay's
  `latch?`), but there's no `nathelper`/`fix_nated_register`. Usually
  unnecessary with a public relay, worth a note.

## Prompt teardown of crashed calls (rtpengine `--b2b-url` analogue)

A handler crash outside offer/answer (`handle_info/3`, `handle_timeout/2`)
kills the call process silently: the ng protocol is request/response, so
Kamailio keeps the SIP dialog up with dead media until someone hangs up.
rtpengine solves this out-of-band — its `--b2b-url` option (with
`xmlrpc-format=2`) calls Kamailio's dialog-module RPC `dlg.terminate_dlg`
(call-id + from-tag + to-tag) when its media timeout fires, and Kamailio
BYEs both legs. Mirror that:

- kamailio.cfg: load `dialog`, call `dlg_manage()` on the initial INVITE,
  expose RPC via `jsonrpcs` over HTTP.
- ex_kamailio: monitor call processes; on abnormal exit POST
  `dlg.terminate_dlg` for that call-id.

## Roadmap (from README "Status")

Not yet implemented; out of scope for the current pass:

- `update` / `query` rtpengine commands
- ICE
- DTLS / SRTP
- transcoding-related extensions
