defmodule ObanBatch.Test.Repo do
  use Ecto.Repo,
    otp_app: :oban_batch,
    adapter: Ecto.Adapters.Postgres
end
