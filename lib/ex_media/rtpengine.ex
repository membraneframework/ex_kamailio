defmodule ExMedia.RtpEngine do
  @moduledoc """
  Behaviour for RTP engine protocol handlers.
  """

  @callback start_link(opts :: Keyword.t()) :: {:ok, pid()} | {:error, any()}
  @callback handle_command(command :: any(), state :: any()) :: {:noreply, any()} | {:reply, any(), any()}
end
