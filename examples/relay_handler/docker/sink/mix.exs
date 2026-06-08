defmodule Sink.MixProject do
  use Mix.Project

  def project do
    [
      app: :sink,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Sink.Application, []}
    ]
  end

  defp deps do
    [
      {:membrane_core, "~> 1.2"},
      {:membrane_udp_plugin, "~> 0.14.3"},
      {:membrane_rtp_plugin, "~> 0.31.3"},
      {:membrane_file_plugin, "~> 0.17.3"}
    ]
  end
end
