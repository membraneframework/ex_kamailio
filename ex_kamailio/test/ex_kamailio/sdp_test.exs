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

  describe "decide_media/2" do
    test "intersects offered PTs with allowed set" do
      {:ok, sdp} = SDP.parse(@offer)
      {pts, dir} = SDP.decide_media(sdp, MapSet.new([0, 101]))
      assert 0 in pts
      assert 101 in pts
      assert dir == "sendrecv"
    end

    test "falls back to defaults when no allowed PTs overlap" do
      {:ok, sdp} = SDP.parse(@offer)
      {pts, _dir} = SDP.decide_media(sdp, MapSet.new([99]))
      # PCMU + telephone-event
      assert pts == [0, 101]
    end

    test "uses sendrecv when remote SDP has no direction attribute" do
      offer_no_dir = String.replace(@offer, "a=sendrecv\r\n", "")
      {:ok, sdp} = SDP.parse(offer_no_dir)
      {_pts, dir} = SDP.decide_media(sdp, MapSet.new([0, 101]))
      assert dir == "sendrecv"
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

  describe "first_audio_endpoint/1" do
    test "extracts IP and port from the first audio m-line" do
      {:ok, sdp} = SDP.parse(@offer)
      assert %Endpoint{ip: ip, rtp_port: 49_170} = SDP.first_audio_endpoint(sdp)
      assert ip == {192, 168, 1, 10}
    end
  end
end
