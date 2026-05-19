defmodule ExKamailio do
  @moduledoc """
  ex_kamailio — Elixir integration for the Kamailio SIP server.

  Implements the [rtpengine][rtpengine] `ng` control protocol over
  WebSocket, encoded as Bencode, so a Kamailio routing script can
  delegate media setup to an Elixir process.

  Plug in your media-handling logic by implementing
  `ExKamailio.Handler` and registering the module via config:

      config :ex_kamailio,
        ws_port: 4003,
        media_ip: System.get_env("MEDIA_IP", "127.0.0.1"),
        port_range: 11_000..40_000,
        handler: MyApp.KamailioHandler

  See `ExKamailio.Handler` for the callback contract and the
  `examples/echo_handler` directory for a runnable end-to-end demo.

  [rtpengine]: https://github.com/sipwise/rtpengine
  """
end
