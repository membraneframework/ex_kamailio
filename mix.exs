defmodule ExMedia.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_media,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ExMedia.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_sdp, "~> 1.1"},
      {:bandit, "~> 1.8"},
      {:websock_adapter, "~> 0.5.8"},
      {:jason, "~> 1.4"},
      {:bento, "~> 1.0"},
      {:plug, "~> 1.18"}
    ]
  end
end
