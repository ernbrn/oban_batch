ExUnit.start()

children = [
  ObanBatch.Test.Repo,
  ObanBatch.State,
  {Oban, Application.get_env(:oban_batch, Oban)}
]

Supervisor.start_link(children, strategy: :one_for_one, name: ObanBatch.Supervisor)
