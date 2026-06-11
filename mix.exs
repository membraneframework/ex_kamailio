defmodule ExKamailio.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/membraneframework-labs/ex_media"

  def project do
    [
      app: :ex_kamailio,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "ExKamailio",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ExKamailio.Application, []}
    ]
  end

  defp deps do
    [
      {:ex_sdp, "~> 1.1"},
      {:bandit, "~> 1.8"},
      {:websock_adapter, "~> 0.5.8"},
      {:bento, "~> 1.0"},
      {:plug, "~> 1.18"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Elixir integration for the Kamailio SIP server via the rtpengine WebSocket control protocol."
  end

  defp package do
    [
      maintainers: ["Membrane Framework Team"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv mix.exs README.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end
end
