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
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_kamailio, path: "../.."},
      {:membrane_core, "~> 1.2"},
      {:membrane_udp_plugin, "~> 0.14.3"},
      {:membrane_tee_plugin, "~> 0.12.0"},
      {:membrane_rtp_plugin, "~> 0.31.3"},
      {:membrane_file_plugin, "~> 0.17.3"},
      {:membrane_g711_ffmpeg_plugin, "~> 0.1.5"},
      {:membrane_rtp_g711_plugin, "~> 0.3.3"},
      {:membrane_wav_plugin, "~> 0.10.2"}
    ]
  end
end
