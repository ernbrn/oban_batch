# ObanBatch

A mixin to provide batch callback functionality with Oban.

## Installation

1. Bring the `lib/oban_batch` files into your project
2. Include `ObanBatch.State` in your application's supervision tree:

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  @moduledoc false

  use Application

  alias MyApp.Repo

  def start(_type, _args) do
    children = [
      Repo,
      Endpoint,
      {Oban, oban_config()},
      ObanBatch.State
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
```

## How to use

Turn any worker into an `ObanBatch.Worker`. A batch worker must define a `perform_with_batch` function. This function behaves just like Oban's `perform` function, except it receives an additional argument: a unique `batch_id`. Any jobs the batch worker enqueues with the `batch_id` in the arguments will be a member of the batch. Any jobs those jobs enqueue with the same `batch_id` will also be a member of the batch.

A batch worker may also define any of three optional callbacks: `on_complete`, `on_success`, and `on_discard`.

When all jobs in the batch have finished running (are in a `completed` or `discarded` state), the callbacks defined in the batch worker module will be executed. 


`on_complete` will get called when all jobs in the batch are in a finished state -- "completed" or "discarded".

`on_success` will get called when all jobs in the batch are successful (have a "completed" state)

`on_failure` will get called when all jobs in the batch are in a finished state and at least one has a "discarded" state.


```elixir
defmodule MyApp.Workers.EmailQueuer do
  alias MyApp.Workers.EmailSender
  alias MyApp.Workers.Notifier

  # Pass any Oban worker options to ObanBatch.Worker
  use ObanBatch.Worker, queue: :default

  @impl ObanBatch.Worker
  def perform_with_batch(args, batch_id, _job) do
    Enum.each(1...1000, fn _ ->

      # By adding the batch_id to the args,
      # these jobs will belong to the batch
      %{batch_id: batch_id}
      |> EmailSender.new()
      |> Oban.insert()
    end)

    # This job will not belong to the batch
    %{message: "Some message"}
    |> Notifier.new()
    |> Oban.insert()
  end

  @impl ObanBatch.Worker
  def on_complete(_batch_id) do
    IO.puts("All 1000 jobs have finished running")
    # Do anything here
  end

  @impl ObanBatch.Worker
  def on_success(_batch_id) do
    IO.puts("All 1000 jobs were successful")
    # Do anything here
  end

  @impl ObanBatch.Worker
  def on_discard(_batch_id) do
    IO.puts("There was at least one failure")
    # Do anything here
  end
end
```

## Roadmap

* Fault tolerance with a database layer to keep track of batches and rescue orphans upon app startup
* Add to Hex 

## Run the tests

Set them up:
```
mix test.setup
```

Run 'em: 
```
mix test
```