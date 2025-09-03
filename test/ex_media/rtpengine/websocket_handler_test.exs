defmodule ExMedia.RtpEngine.WebSocketHandlerTest do
  use ExUnit.Case, async: true
  alias ExMedia.RtpEngine.WebSocketHandler

  describe "handle_in/2" do
    test "sends response for offer command" do
      sdp = "v=0\r\no=- 123456 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n"
      command = %{"command" => "offer", "sdp" => sdp}
      state = %{conn: %{send_frame: fn _frame -> :ok end}}
      assert {:ok, _state} = WebSocketHandler.handle_in({:text, Jason.encode!(command)}, state)
      # Verify response is sent (you can mock Bandit.WebSocket.send_frame or check logs)
    end

    test "handles invalid command" do
      command = %{"command" => "unknown"}
      state = %{conn: %{send_frame: fn _frame -> :ok end}}
      assert {:ok, _state} = WebSocketHandler.handle_in({:text, Jason.encode!(command)}, state)
      # Verify error is logged
    end
  end
end
