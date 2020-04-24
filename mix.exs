defmodule ObanBatch.MixProject do
  use Mix.Project

  def project do
    [
      app: :oban_batch,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
      preferred_cli_env: [
        "test.setup": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:oban, "~> 1.2"},
      {:telemetry, "~> 0.4"},
      {:ecto_sql, "~> 3.1"}
    ]
  end

  defp aliases do
    [
      "test.setup": ["ecto.create", "ecto.migrate"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]
end
