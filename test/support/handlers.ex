# CallHandler implementations shared across the test suites, one per scenario.
defmodule ExKamailio.TestHandlers do
  @moduledoc false

  defmodule ApiHandler do
    @moduledoc false
    use ExKamailio.CallHandler

    @impl true
    def init(_session, opts), do: {:ok, %{report_to: opts[:report_to]}}

    @impl true
    def handle_offer(_offer, session, st) do
      send(st.report_to, {:offer, session.call_id})
      {:ok, ExSDP.new(), st}
    end

    @impl true
    def handle_answer(_answer, session, st) do
      send(st.report_to, {:answer, session.call_id, session.to_tag})
      {:ok, ExSDP.new(), st}
    end

    @impl true
    def handle_delete(session, st) do
      send(st.report_to, {:delete, session.call_id})
      :ok
    end

    @impl true
    def handle_info(msg, session, st) do
      send(st.report_to, {:info, session.call_id, msg})
      {:ok, st}
    end
  end

  defmodule MinimalHandler do
    @moduledoc false
    use ExKamailio.CallHandler

    @impl true
    def init(_session, _opts), do: {:ok, %{}}

    @impl true
    def handle_offer(_offer, _session, st), do: {:ok, ExSDP.new(), st}

    @impl true
    def handle_answer(_answer, _session, st), do: {:ok, ExSDP.new(), st}
  end

  defmodule ExtendHandler do
    @moduledoc false
    use ExKamailio.CallHandler

    @impl true
    def init(_session, opts), do: {:ok, %{report_to: opts[:report_to]}}

    @impl true
    def handle_offer(_offer, _session, st), do: {:ok, ExSDP.new(), st}

    @impl true
    def handle_answer(_answer, _session, st), do: {:ok, ExSDP.new(), st}

    @impl true
    def handle_idle(session, st) do
      send(st.report_to, {:idle, session.call_id})
      {:ok, st}
    end
  end

  defmodule SlowHandler do
    @moduledoc false
    use ExKamailio.CallHandler

    @impl true
    def init(_session, opts), do: {:ok, %{report_to: opts[:report_to]}}

    @impl true
    def handle_offer(_offer, _session, st) do
      Process.sleep(200)
      {:ok, ExSDP.new(), st}
    end

    @impl true
    def handle_answer(_answer, _session, st), do: {:ok, ExSDP.new(), st}

    @impl true
    def handle_delete(session, st) do
      send(st.report_to, {:delete, session.call_id})
      :ok
    end
  end

  defmodule CrashHandler do
    @moduledoc false
    use ExKamailio.CallHandler

    @impl true
    def init(_session, _opts), do: {:ok, %{}}

    @impl true
    def handle_offer(_offer, _session, _st), do: raise("boom")

    @impl true
    def handle_answer(_answer, _session, st), do: {:ok, ExSDP.new(), st}
  end

  defmodule InitSessionHandler do
    @moduledoc false
    use ExKamailio.CallHandler

    @impl true
    def init(session, opts) do
      send(opts[:report_to], {:init_session, session})
      {:ok, %{}}
    end

    @impl true
    def handle_offer(_offer, _session, st), do: {:ok, ExSDP.new(), st}

    @impl true
    def handle_answer(_answer, _session, st), do: {:ok, ExSDP.new(), st}
  end
end
