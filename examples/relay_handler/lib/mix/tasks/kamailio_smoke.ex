defmodule Mix.Tasks.Kamailio.Smoke do
  @moduledoc """
  End-to-end smoke test against a running ex_kamailio.

  Connects to `ws://<host>:<port>/` over a real WebSocket, replays a
  realistic Kamailio rtpengine exchange (`ping`, then a full
  `offer` -> `answer` -> `delete` cycle), and prints the decoded
  Bencode replies.

  Run it in one terminal after starting the example app in another:

      # terminal 1
      iex -S mix       # boots ex_kamailio + relay_handler on :4003

      # terminal 2
      mix kamailio.smoke

  Options:

      --host HOST   (default: 127.0.0.1)
      --port PORT   (default: 4003)
  """

  @shortdoc "Drive a running ex_kamailio over WebSocket without Kamailio."

  use Mix.Task

  require Logger

  @offer_sdp """
  v=0\r
  o=alice 1 1 IN IP4 10.0.0.10\r
  s=-\r
  c=IN IP4 10.0.0.10\r
  t=0 0\r
  m=audio 49170 RTP/AVP 0 101\r
  a=rtpmap:0 PCMU/8000\r
  a=rtpmap:101 telephone-event/8000\r
  a=sendrecv\r
  """

  @answer_sdp """
  v=0\r
  o=bob 2 2 IN IP4 10.0.0.20\r
  s=-\r
  c=IN IP4 10.0.0.20\r
  t=0 0\r
  m=audio 50000 RTP/AVP 0 101\r
  a=rtpmap:0 PCMU/8000\r
  a=rtpmap:101 telephone-event/8000\r
  a=sendrecv\r
  """

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: [host: :string, port: :integer])
    host = Keyword.get(opts, :host, "127.0.0.1")
    port = Keyword.get(opts, :port, 4003)

    Mix.Task.run("app.start")
    {:ok, _} = Application.ensure_all_started(:mint_web_socket)

    call_id = "smoke-#{System.unique_integer([:positive])}"
    IO.puts("→ connecting to ws://#{host}:#{port}/")

    {:ok, conn} = connect(host, port)

    send_frame!(conn, "00001", %{command: "ping"})
    expect!(conn, "00001", "pong-or-error")

    send_frame!(conn, "00002", %{
      command: "offer",
      "call-id": call_id,
      "from-tag": "smoke-from",
      sdp: @offer_sdp
    })

    offer_reply = expect!(conn, "00002", "offer reply")

    send_frame!(conn, "00003", %{
      command: "answer",
      "call-id": call_id,
      "from-tag": "smoke-from",
      "to-tag": "smoke-to",
      sdp: @answer_sdp
    })

    expect!(conn, "00003", "answer reply")

    send_frame!(conn, "00004", %{command: "delete", "call-id": call_id})
    expect!(conn, "00004", "delete reply")

    case offer_reply do
      %{"result" => "ok", "rtp_port" => p, "rtcp_port" => q} ->
        IO.puts("✓ ex_kamailio allocated local media ports #{p}/#{q} for the caller")

      _ ->
        IO.puts("⚠ offer reply was unexpected: #{inspect(offer_reply)}")
    end

    IO.puts("✓ smoke test complete")
  end

  # -- WebSocket plumbing on top of Mint --

  defp connect(host, port) do
    {:ok, conn} = Mint.HTTP.connect(:http, host, port, protocols: [:http1])
    {:ok, conn, ref} = Mint.WebSocket.upgrade(:ws, conn, "/", [])

    {:ok, conn, websocket} = receive_upgrade(conn, ref)
    {:ok, %{conn: conn, websocket: websocket, ref: ref}}
  end

  defp receive_upgrade(conn, ref) do
    receive do
      msg ->
        {:ok, conn, responses} = Mint.WebSocket.stream(conn, msg)

        case Enum.reduce(responses, {nil, nil}, fn
               {:status, ^ref, status}, {_, headers} -> {status, headers}
               {:headers, ^ref, headers}, {status, _} -> {status, headers}
               _, acc -> acc
             end) do
          {status, headers} when is_integer(status) and is_list(headers) ->
            {:ok, conn, websocket} = Mint.WebSocket.new(conn, ref, status, headers)
            {:ok, conn, websocket}

          _ ->
            receive_upgrade(conn, ref)
        end
    end
  end

  defp send_frame!(state, cookie, payload) do
    body = payload |> Bento.encode!() |> IO.iodata_to_binary()
    frame = {:text, cookie <> " " <> body}
    IO.puts("→ #{cookie} #{inspect(payload, limit: :infinity, printable_limit: 60)}")
    {:ok, websocket, data} = Mint.WebSocket.encode(state.websocket, frame)
    {:ok, conn} = Mint.WebSocket.stream_request_body(state.conn, state.ref, data)
    Map.merge(state, %{websocket: websocket, conn: conn})
  end

  defp expect!(state, cookie, label) do
    receive do
      msg ->
        case Mint.WebSocket.stream(state.conn, msg) do
          {:ok, conn, [{:data, _ref, data}]} ->
            {:ok, _websocket, [{:text, text}]} = Mint.WebSocket.decode(state.websocket, data)
            <<^cookie::binary-size(byte_size(cookie)), " ", body::binary>> = text
            {:ok, decoded} = Bento.decode(body)
            IO.puts("← #{cookie} (#{label}) #{inspect(decoded, limit: :infinity)}")
            put_in(state.conn, conn)
            decoded

          other ->
            Mix.raise("unexpected reply for #{label}: #{inspect(other)}")
        end
    after
      2_000 -> Mix.raise("timeout waiting for #{label}")
    end
  end
end
