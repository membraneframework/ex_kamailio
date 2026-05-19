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

## Test path B — real Kamailio + SIPp

End-to-end through a real Kamailio process bridging SIP signaling to
ex_kamailio over WebSocket. Uses the existing
`../../../priv/kamailio.cfg` and SIPp scenarios.

### Prerequisites

- Kamailio with the `rtpengine` and `lwsc` modules:
  ```sh
  # Debian/Ubuntu
  sudo apt install kamailio kamailio-presence-modules kamailio-websocket-modules
  # The lwsc module is shipped in kamailio-websocket-modules.
  ```
- SIPp:
  ```sh
  sudo apt install sip-tester        # or `brew install sipp` on macOS
  ```

### Configure

Edit `priv/kamailio.cfg` and replace `192.168.36.74` with the IP of the
host running Kamailio + echo_handler (must be reachable from the SIPp
clients). The three lines to update:

```
listen=udp:<YOUR_IP>:5060
modparam("rtpengine", "rtpengine_sock", "ws://<YOUR_IP>:4003")
$du = "sip:1000@<YOUR_IP>:5070";       # UAS destination
```

Set the same IP in the example app's config or via env:

```sh
export MEDIA_IP=<YOUR_IP>
```

### Run

In four terminals:

```sh
# 1. ex_kamailio + echo_handler (listens on :4003 for Kamailio)
iex -S mix

# 2. SIPp UAS — answers calls on :5070
sipp -sf ../../../priv/sipp_uas.xml -p 5070

# 3. Kamailio — proxies SIP from :5060 to UAS at :5070, talks to ex_kamailio
sudo kamailio -f ../../../priv/kamailio.cfg -DD

# 4. SIPp UAC — places one INVITE at Kamailio:5060
sipp -sf ../../../priv/sipp_uac.xml <YOUR_IP>:5060 -m 1
```

### What to watch

- **echo_handler logs**: `[echo] offer …` / `[echo] answer …` /
  `[echo] delete …` show each rtpengine command arriving from Kamailio.
- **Kamailio logs (`-DD` keeps it foregrounded)**: `rtpengine_offer`
  and `rtpengine_answer` should return success. If `rtpengine_offer
  failed`, the WebSocket connection to ex_kamailio is failing — check
  `MEDIA_IP`, the `ws://` URL, and that `lwsc.so` is loaded.
- **SIPp UAC**: should show one successful call.

### Troubleshooting

- **"rtpengine_offer failed"** — Kamailio can't reach ex_kamailio. Try
  `mix kamailio.smoke --host <YOUR_IP>` from the Kamailio host to
  confirm the WS port is reachable.
- **No audio** — expected; this example does no media bridging. Real
  RTP arrives at the ports ex_kamailio allocated but nothing reads
  them. Real integrations would attach a Membrane (or other) pipeline
  to those ports inside `offer/2` and `answer/2`.
- **Kamailio fails to load `lwsc.so`** — install the
  `kamailio-websocket-modules` package (Debian/Ubuntu) or the
  equivalent for your distro.
