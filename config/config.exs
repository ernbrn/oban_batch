use Mix.Config

config :oban_batch, ObanBatch.Test.Repo,
  priv: "test/support/",
  url: System.get_env("DATABASE_URL") || "postgres://localhost:5432/oban_batch_test",
  pool: Ecto.Adapters.SQL.Sandbox

config :oban_batch,
  ecto_repos: [ObanBatch.Test.Repo]

config :oban_batch, Oban, repo: ObanBatch.Test.Repo

config :logger, level: :warn
