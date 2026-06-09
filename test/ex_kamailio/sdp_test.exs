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

  describe "answer_sdp/5" do
    test "produces an answer with the given endpoint and direction" do
      body = SDP.answer_sdp("192.0.2.10", 40_000, 40_001, [0, 101], "sendrecv")
      assert body =~ "v=0"
      assert body =~ "m=audio 40000 RTP/AVP 0 101"
      assert body =~ "c=IN IP4 192.0.2.10"
      assert body =~ "a=rtcp:40001"
      assert body =~ "a=sendrecv"
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

  describe "first_audio_endpoint/1" do
    test "extracts IP and port from the first audio m-line" do
      {:ok, sdp} = SDP.parse(@offer)
      assert %Endpoint{ip: ip, rtp_port: 49_170} = SDP.first_audio_endpoint(sdp)
      assert ip == {192, 168, 1, 10}
    end
  end
end
