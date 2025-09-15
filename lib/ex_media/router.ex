defmodule ExMedia.Router do
  use Plug.Router
  require Logger

  plug :match
  plug :dispatch

  get "/health" do
    send_resp(conn, 200, "ok")
  end

  #get "/rtpengine" do
  get "/" do
    # Upgrade to WebSocket using WebSock
    conn
    |> WebSockAdapter.upgrade(ExMedia.WebSocket, %{}, [timeout: 300000])
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
