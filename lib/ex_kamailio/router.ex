defmodule ExKamailio.Router do
  @moduledoc false
  use Plug.Router
  require Logger

  plug(:match)
  plug(:dispatch)

  get "/health" do
    send_resp(conn, 200, "ok")
  end

  # rtpengine clients connect here and immediately upgrade.
  get "/" do
    WebSockAdapter.upgrade(conn, ExKamailio.WebSocket, %{}, timeout: 6_000_000)
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
