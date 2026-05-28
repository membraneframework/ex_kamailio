# Next: real-softphone call through the relay

Baseline (Docker SIPp-to-SIPp E2E) is tagged `relay-docker-e2e-v1`.
One task left to place a real call between LAN softphones (or a phone
and a softphone) through this stack on macOS + Colima.

## Task 1 — Kamailio cfg: REGISTER + location lookup ✅ DONE

Landed in commit `b738370`.

- `usrloc.so` + `registrar.so` loaded (usrloc first; registrar binds
  to usrloc at mod_init)
- `modparam("usrloc", "db_mode", 0)` — in-memory location table
- REGISTER branch calls `save("location")`
- INVITE branch calls `lookup("location")` before `rtpengine_offer`;
  404 on miss; no auth (LAN demo)

Test rig changes that came with it:

- New one-shot `sipp-register` service. A single sipp instance can't
  both initiate a REGISTER (scenario starts with `<send>` → UAC mode)
  and accept INVITEs with new Call-IDs (no Call-ID match). So
  registration is split into a `-m 1` container that exits.
- `sipp/register.xml` — the REGISTER scenario; Contact is hardcoded
  to `sip:1000@sipp-uas:5070` so Kamailio routes there.
- `sipp-uas` reverts to a pure UAS (no REGISTER prefix).

### How to run the Docker E2E now

```sh
docker compose up -d --build relay kamailio sink sipp-uas
docker compose run --rm sipp-register   # populates Kamailio's usrloc
docker compose run --rm sipp-uac        # places the call
ffplay -f alaw -ar 8000 -ac 1 recordings/uas.alaw
```

Gotcha: **do not `rm` `recordings/uas.alaw` while the `sink`
container is running.** The sink opens the file once at startup and
holds the fd for its lifetime; deleting the dirent leaves writes
going to an unlinked inode that never reappears. For a fresh capture
run `docker compose restart sink` instead — `handle_setup` truncates
on reopen.

## Task 2 — Networking: make LAN peers reach the relay

The Colima VM is currently on its internal NAT (`192.168.5.1/24`),
not on the LAN. Two changes are needed:

1. **Colima**: `colima stop && colima start --network-address`
   (one-time; prompts for sudo, uses vmnet to give the VM a real LAN
   IP). Verify with `colima list` — the `ADDRESS` column should show
   a `192.168.x.x` that's on your LAN.

2. **Compose** (`docker/compose.yml`):
   - Add `network_mode: host` to the `kamailio` service and drop its
     bridge-network-specific config
   - Same for `relay` — and set `MEDIA_IP` to the colima VM's LAN IP
     (export it from a shell var, don't hardcode in YAML)
   - Leave `sipp-uas`, `sink`, `sipp-register` on the bridge if you
     want; they're only used by the existing internal test, not the
     real-call demo

Softphones then point at the VM's LAN IP, port 5060 — REGISTER from
each, then dial each other by AOR.

## Why no library change is needed

Checked on 2026-05-28. The SDP-advertised address comes from one
place:

- `lib/ex_kamailio/websocket.ex:33` — reads `:media_ip` from app
  config
- `lib/ex_kamailio/websocket.ex:96, :167` — stamps it into
  `caller_local.ip` / `callee_local.ip`
- `examples/relay_handler/lib/relay_handler.ex:92-94` — `answer_for/1`
  passes that IP straight into `SDP.answer_sdp/5`

And it's already wired to env: `config/config.exs:5` reads
`System.get_env("MEDIA_IP", ...)`. The relay binds on `:any`
(`relay_handler.ex:64`), so changing `MEDIA_IP` only affects the
advertised SDP — not the bind socket. So switching from the bridge to
the LAN VM IP is a single env-var change, no patch to the library.

## macOS / Colima caveats

- vmnet needs root once at `colima start`
- macOS firewall sometimes drops UDP to virtual interfaces; allow
  Colima / the vmnet daemon in System Settings → Privacy & Security →
  Firewall if signaling reaches Kamailio but media doesn't
- Expect to spend an hour on networking goop the first time

## Rollback

```sh
git checkout relay-docker-e2e-v1     # known-good Docker E2E
git diff   relay-docker-e2e-v1..HEAD # see what changed since
```
