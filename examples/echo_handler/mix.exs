defmodule EchoHandler.MixProject do
  use Mix.Project

  def project do
    [
      app: :echo_handler,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {EchoHandler.Application, []}
    ]
  end

  defp deps do
    [
      {:ex_kamailio, path: "../.."},
      # WebSocket client used by the `mix kamailio.smoke` task to fake-drive
      # ex_kamailio over the loopback, no real Kamailio required.
      {:mint_web_socket, "~> 1.0"}
    ]
  end
end
