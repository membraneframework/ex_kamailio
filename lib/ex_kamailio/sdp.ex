defmodule ExKamailio.SDP do
  @moduledoc """
  SDP parsing helper — a thin wrapper over `ExSDP`.
  """

  @doc """
  Parse a textual SDP body. Returns the `%ExSDP{}` struct on success.
  """
  @spec parse(String.t() | nil) :: {:ok, ExSDP.t()} | {:error, term()}
  def parse(nil), do: {:error, :no_sdp}

  def parse(text) when is_binary(text) do
    case ExSDP.parse(text) do
      {:ok, sdp} -> {:ok, sdp}
      {:error, error} -> {:error, error}
    end
  rescue
    error -> {:error, error}
  end
end
