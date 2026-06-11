defmodule ExKamailio.SDPTest do
  use ExUnit.Case, async: true

  alias ExKamailio.{Endpoint, SDP}

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

  describe "rewrite_endpoint/2" do
    test "repoints media at the endpoint while preserving the offered codecs" do
      {:ok, sdp} = SDP.parse(@offer)
      local = %Endpoint{ip: {192, 0, 2, 10}, rtp_port: 40_000, rtcp_port: 40_001}

      out = SDP.rewrite_endpoint(sdp, local)
      assert %ExSDP{} = out
      assert out.connection_data.address == {192, 0, 2, 10}

      body = to_string(out)
      # codec list from the offer is preserved verbatim
      assert body =~ "m=audio 40000 RTP/AVP 0 8 101"
      assert body =~ "c=IN IP4 192.0.2.10"
      assert body =~ "a=rtcp:40001"
    end

    test "accepts an FQDN endpoint" do
      {:ok, sdp} = SDP.parse(@offer)
      out = SDP.rewrite_endpoint(sdp, %Endpoint{ip: "host.docker.internal", rtp_port: 5_000})

      body = to_string(out)
      assert body =~ "c=IN IP4 host.docker.internal"
      assert body =~ "m=audio 5000"
    end
  end
end
