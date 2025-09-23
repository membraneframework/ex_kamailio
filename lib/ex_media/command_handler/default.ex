defmodule ExMedia.CommandHandler.Default do
  @moduledoc false
  use GenServer
  require Logger


  @behaviour ExMedia.CommandHandler


  alias ExMedia.{PortPool, SDPAdapter}
  #alias ExMedia.SessionStore

  @impl true
  def handle_command(cmd), do: GenServer.call(__MODULE__, {:command, cmd})


  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)


  # -- GenServer --
  @impl true
  def init(_opts) do
    Logger.info("initializing command handler instance")
    {:ok,
      %{
        sessions: %{},
        media_ip: Application.fetch_env!(:ex_media, :media_ip),
        allowed_pts: MapSet.new(Application.get_env(:ex_media, :allowed_pts, []))
       }
    }
  end


  @impl true
  def handle_call({:command, cmd}, _from, state) do
    IO.inspect(cmd)
    case route(cmd, state) do
      {:reply, io, st} -> {:reply, {:ok, IO.iodata_to_binary(io)}, st}
      {:error, reason, st} -> {:reply, {:error, reason}, st}
    end
  end


  # -- routing --
  defp route(%{"command" => "offer"} = cmd, s), do: do_offer(cmd, s)
  defp route(%{"command" => "answer"} = cmd, s), do: do_answer(cmd, s)
  defp route(%{"command" => "delete"} = cmd, s), do: do_delete(cmd, s)
  defp route(cmd, s), do: {:error, {:unknown_command, cmd}, s}


  # -- OFFER --
  defp do_offer(cmd, state) do
    call_id = fetch(cmd, ["call-id"], "unknown")
    from_tag = fetch(cmd, ["from-tag"], "ftag")


    remote = SDPAdapter.parse(Map.get(cmd, :sdp) || Map.get(cmd, "sdp"))
    remote_offer =
      Enum.map(remote.media,
        fn %ExSDP.Media{port: port, connection_data: %{address: ip}} ->
          {:inet.ntoa(ip) |> to_string(), port}
        end)

    {pts, dir} = SDPAdapter.decide_media(remote, state.allowed_pts)
    Logger.debug("remote #{inspect remote}, pts = #{inspect pts}, dir = #{inspect dir}")

    with {:ok, {rtp, rtcp, _rtp_sock, _rtcp_sock}} <- PortPool.checkout({call_id, from_tag}) do
      sdp = SDPAdapter.answer_sdp(state.media_ip, rtp, rtcp, pts, dir)
      Logger.info(%{callid: call_id, offer: %{"from-tag" => from_tag, "rtp port" => rtp}})
      sess = %{
        call_id: call_id,
        from_tag: from_tag,
        state: :offered,
        offer: %{remote: remote_offer, local: {state.media_ip, rtp}}
      }
      case ExMedia.Membrane.Pipeline.create(call_id) do
        {:ok, sup_pid, pipeline_pid} ->
          new_sess = sess
          |> Map.put(:pipeline_pid,  pipeline_pid)
          |> Map.put(:pipeline_sup_pid, sup_pid)
          Logger.info(%{call: call_id, session: new_sess})
          :ok = ExMedia.SessionTable.put_session(new_sess)
          :ok = ExMedia.Membrane.Pipeline.update(new_sess, :client)
          reply = Bento.encode!(%{result: "ok", sdp: sdp, rtp_port: rtp, rtcp_port: rtcp})
          {:reply, reply, state}
        other ->
          Logger.error(%{call: call_id, pipeline_error: other})
          {:reply, Bento.encode!(%{"result" => "error", "error-reason" => "unknown call"}), state}
      end
    else
      {:error, reason} ->
        Logger.error(%{call: call_id, port_checkout_error: reason})
        {:reply, Bento.encode!(%{"result" => "error", "error-reason" => "port pool exhausted"}), state}
    end
  end


  # -- ANSWER --
  defp do_answer(cmd, state) do
    call_id = fetch(cmd, ["call-id"], "unknown")
    from_tag = fetch(cmd, ["from-tag"], "ftag")
    to_tag = fetch(cmd, ["to-tag"], "ftag")

    #Logger.debug(%{state: state})
    Logger.info(%{callid: call_id, answer: %{"from-tag" => from_tag, "to-tag" => to_tag}})


    case ExMedia.SessionTable.get_session(call_id) do
      sess when is_map(sess) ->
        remote = SDPAdapter.parse(Map.get(cmd, :sdp) || Map.get(cmd, "sdp"))
        remote_answer =
          Enum.map(remote.media,
            fn %ExSDP.Media{port: port, connection_data: %{address: ip}} ->
              {:inet.ntoa(ip) |> to_string(), port}
            end)
        {pts, dir} = SDPAdapter.decide_media(remote, state.allowed_pts)
        {:ok, {rtp, rtcp, _rtp_sock, _rtcp_sock}} = PortPool.checkout({call_id, from_tag})
        sdp = SDPAdapter.answer_sdp(state.media_ip, rtp, rtcp, pts, dir)
        reply = Bento.encode!(%{result: "ok", sdp: sdp})
        new_sess =
          sess
          |> Map.put(:answer, %{remote: remote_answer, local: {state.media_ip,rtp}})
        :ok = ExMedia.SessionTable.put_session(new_sess)
        {:reply, reply, state}
      :nil ->
        {:reply, Bento.encode!(%{"result" => "error", "error-reason" => "unknown call"}), state}

    end
  end

  defp do_delete(cmd, state) do
    call_id = fetch(cmd, ["call-id"], "unknown")
    case ExMedia.SessionTable.get_session(call_id) do
      sess when is_map(sess) ->
        :ok = ExMedia.SessionTable.delete(call_id)
        {:reply, Bento.encode!(%{result: "ok"}), state}
      :nil ->
        {:reply, Bento.encode!(%{"result" => "error", "error-reason" => "unknown call"}), state}

    end
  end


  defp fetch(map, keys, default), do: Enum.find_value(keys, default, &Map.get(map, &1))

end
