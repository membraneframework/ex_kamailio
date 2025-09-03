defmodule ExMedia.RtpEngine.UDPTest do
  use ExUnit.Case, async: true
  alias ExMedia.RtpEngine.UDP

  setup do
    {:ok, pid} = UDP.start_link(port: 0, name: :test_udp)
    {:ok, %{pid: pid}}
  end

  describe "handle_command/2" do
    test "sends response for offer command", %{pid: pid} do
      sdp = "v=0\r\no=- 123456 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n"
      command = %{"command" => "offer", "sdp" => sdp, "ip" => {127, 0, 0, 1}, "port" => 12345}
      assert :ok = GenServer.call(pid, {:handle_command, command})
      # Verify response is sent (you can mock :gen_udp.send or check logs)
    end

    test "handles invalid command", %{pid: pid} do
      command = %{"command" => "unknown"}
      assert :ok = GenServer.call(pid, {:handle_command, command})
      # Verify error is logged
    end
  end
end
