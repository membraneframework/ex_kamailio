# echo_handler

A minimal example showing how to wire up `ex_kamailio` with a user-defined
`ExKamailio.Handler`. The handler logs every SDP it receives and answers
with a sendrecv SDP pointing at the local endpoint that ex_kamailio has
allocated.

## Setup

```sh
mix deps.get
```

## Test path A — smoke test, no Kamailio required

Boots the app and drives ex_kamailio over a real WebSocket on the
loopback. Verifies the whole protocol path (Bandit → Bencode →
handler → reply) but does not exercise actual SIP signaling.

```sh
mix kamailio.smoke
```

Expected: the task prints the decoded Bencode replies for `ping`,
`offer`, `answer`, and `delete`. The `[echo]` log lines show the
handler being invoked with the parsed session.

To point at a different host/port:

```sh
mix kamailio.smoke --host 192.168.36.74 --port 4003
```

## Test path B — real Kamailio + SIPp in Docker

A docker-compose rig with Kamailio + two SIPp endpoints drives a real
SIP call end-to-end through ex_kamailio over WebSocket. Works on
macOS via Colima or Docker Desktop.

See [`docker/README.md`](docker/README.md) for the full recipe.

Quick summary:

```sh
# Terminal 1: ex_kamailio + echo_handler on the host
mix run --no-halt

# Terminal 2: Kamailio + SIPp UAS
cd docker && docker compose up -d kamailio sipp-uas

# Terminal 3: place one call and watch the offer/answer/delete log lines in terminal 1
docker compose run --rm sipp-uac
```
