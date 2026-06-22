defmodule ExKamailio.SDPTest do
  use ExUnit.Case, async: true

  alias ExKamailio.SDP

  @offer """
  v=0\r
  o=alice 2890844526 2890844526 IN IP4 192.168.1.10\r
  s=-\r
  c=IN IP4 192.168.1.10\r
  t=0 0\r
  m=audio 49170 RTP/AVP 0 8 101\r
  a=sendrecv\r
  """

  describe "parse/1" do
    test "returns parsed SDP struct" do
      assert {:ok, %ExSDP{}} = SDP.parse(@offer)
    end

    test "returns error for nil" do
      assert {:error, :no_sdp} = SDP.parse(nil)
    end

    test "returns error tuple for garbage" do
      assert {:error, _} = SDP.parse("not sdp")
    end
  end
end
