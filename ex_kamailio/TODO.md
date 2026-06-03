# ex_kamailio — deferred work

Running list of things we deliberately put off. Nothing here blocks current
functionality; it's a reminder so the decisions don't get lost.

## Orphaned code — decide: delete, or keep as opt-in

`ex_kamailio` is a **pure SDP forwarder**: it hands the parsed offer/answer to the
handler and ships back whatever SDP the handler returns. It does NOT decide
codecs. That left some code with no caller:

- **`SDP.decide_media/2`** and its private helpers (`intersect_pts`,
  `default_pts`, `to_pt_set`, `extract_remote_audio`), plus the **`:allowed_pts`
  config key.** Originally meant for library-side codec negotiation, now unused.
  Decide: remove entirely, or document and expose as an opt-in helper for
  handlers that want to filter codecs themselves.

- **`SDP.answer_sdp/5`** — builds a minimal SDP answer from scratch. Superseded in
  the examples by `SDP.rewrite_endpoint/2` (which preserves the peer's codecs).
  Decide: remove, or keep as a from-scratch builder for handlers that don't want
  to echo the offer.

## Before any Hex release

- **Tag `v0.1.0`.** `mix.exs` sets `docs: [source_ref: "v#{@version}"]`, but no
  git tag exists yet, so the "source" links in generated HexDocs will 404.

- **`source_url` vs. repo layout.** `mix.exs` points `source_url` at
  `github.com/membraneframework-labs/ex_media`, but the library lives in the
  `ex_kamailio/` subdirectory of that repo. Decide the strategy (own repo, or
  keep as a monorepo subdir) and fix `source_url` / HexDocs source links /
  `package: [files: ...]` accordingly.

## Roadmap (from README "Status")

Not yet implemented; out of scope for the current pass:

- `update` / `query` rtpengine commands
- ICE
- DTLS / SRTP
- transcoding-related extensions
