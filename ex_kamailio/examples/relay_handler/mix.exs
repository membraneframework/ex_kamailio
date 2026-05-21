defmodule RelayHandler.MixProject do
  use Mix.Project

  def project do
    [
      app: :relay_handler,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {RelayHandler.Application, []}
    ]
  end

  defp deps do
    [
      {:ex_kamailio, path: "../.."},
      {:membrane_core, "~> 1.2"},
      {:membrane_udp_plugin, "~> 0.14"}
    ]
  end
end
