defmodule ExKamailio.UtilsTest do
  use ExUnit.Case, async: true

  alias ExKamailio.Utils

  test "detect_media_ip/0 returns a parseable IPv4 string" do
    ip = Utils.detect_media_ip()
    assert is_binary(ip)
    assert {:ok, {_, _, _, _}} = :inet.parse_address(String.to_charlist(ip))
  end

  test "resolve_media_ip/1 resolves :auto and \"auto\" via detect_media_ip/0" do
    assert Utils.resolve_media_ip(:auto) == Utils.detect_media_ip()
    assert Utils.resolve_media_ip("auto") == Utils.detect_media_ip()
  end

  test "resolve_media_ip/1 passes a literal through unchanged" do
    assert Utils.resolve_media_ip("203.0.113.7") == "203.0.113.7"
  end
end
