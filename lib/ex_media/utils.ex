defmodule ExMedia.Utils do

  @moduledoc """
  Useful functions
  """
  def parse_ip!(string) do
    {:ok, ip} = :inet.parse_address(String.to_charlist(string))
    ip
  end
end
