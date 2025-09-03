defmodule ExMedia.RtpEngine.CommandHandlerTest do
  use ExUnit.Case, async: true
  alias ExMedia.RtpEngine.CommandHandler

  describe "handle_command/2" do
    test "offer command with valid SDP" do
      sdp = "v=0\r\no=- 123456 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n"
      params = %{"command" => "offer", "sdp" => sdp}
      assert {:ok, response} = CommandHandler.handle_command("offer", params)
      assert response["command"] == "offer_response"
      assert String.contains?(response["sdp"], "# Transformed by ExMedia")
    end

    test "offer command with invalid SDP" do
      params = %{"command" => "offer", "sdp" => "invalid sdp"}
      assert {:error, :invalid_sdp} = CommandHandler.handle_command("offer", params)
    end

    test "answer command (stub)" do
      params = %{"command" => "answer"}
      assert {:ok, :answer_stub} = CommandHandler.handle_command("answer", params)
    end

    test "delete command (stub)" do
      params = %{"command" => "delete"}
      assert {:ok, :delete_stub} = CommandHandler.handle_command("delete", params)
    end

    test "unknown command" do
      params = %{"command" => "unknown"}
      assert {:error, :unknown_command} = CommandHandler.handle_command("unknown", params)
    end
  end
end
