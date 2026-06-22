# ex_kamailio — deferred work

Running list of things we deliberately put off. Nothing here blocks current
functionality; it's a reminder so the decisions don't get lost.

## Before any Hex release

- **Tag `v0.1.0`.** `mix.exs` sets `docs: [source_ref: "v#{@version}"]`, so
  HexDocs "source" links point at `blob/v0.1.0/...`. Create the git tag on the
  published commit, as the last step before `mix hex.publish`:
  `git tag v0.1.0 && git push origin v0.1.0`. (The stray `0.0.1` tag lacks the
  `v` prefix `source_ref` expects — delete or ignore it.)

- **Repo rename `ex_media` → `ex_kamailio`.** Decided: repo and package both
  `ex_kamailio`. `@source_url` in `mix.exs` and the local directory are already
  updated. Remaining manual steps: rename the repo on GitHub (auto-redirects the
  old URL), then `git remote set-url origin
  git@github.com:membraneframework-labs/ex_kamailio.git`.

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

## Decide: keep or delete `SDP.rewrite_endpoint/2`

Kept for now. It's the shuttle primitive ("repoint a parsed SDP at a local
endpoint, preserving its codecs") and the README handler is built on it — but
no shipped code calls it (the relay example builds its PCMU SDP by hand), and
it does no offer/answer mediation; correctness depends on the handler passing
the right SDP in. Decide whether that convenience earns its API surface.

## Roadmap (from README "Status")

Not yet implemented; out of scope for the current pass:

- `update` / `query` rtpengine commands
- ICE
- DTLS / SRTP
- transcoding-related extensions
