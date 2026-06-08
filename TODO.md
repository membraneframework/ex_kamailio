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

## Robustness / known gaps (pre-existing)

Noticed while debugging the Kamailio connection-pool behavior; worth hardening:

- **An offered-but-never-`delete`d call leaks its caller RTP port.**
  `SessionTable` GC drops the stale session after 30 min but does not call
  `PortPool.release/2` — only `delete` frees ports. If Kamailio ever fails to
  send `delete` (some cancel/failure paths), that port stays checked out.
  GC should release the ports of any session it reaps.

## Roadmap (from README "Status")

Not yet implemented; out of scope for the current pass:

- `update` / `query` rtpengine commands
- ICE
- DTLS / SRTP
- transcoding-related extensions
