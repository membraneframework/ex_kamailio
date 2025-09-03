defmodule ExMedia.CommandHandler do
  @moduledoc """
  Behaviour for pluggable command handlers.
  """


  @callback handle_command(map()) ::
    {:reply, iodata(), new_state :: term()} |
    {:error, term(), new_state :: term()}
end
