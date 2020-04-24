defmodule ObanBatch.Worker do
  @moduledoc """
  Defines a behavior and macro to allow a worker module to enqueue new jobs within a batch.

  Worker modules that create a batch must define a `perform_with_batch/3` function, which is
  called with an `args` struct, a batch_id, and the full `Oban.Job` struct. They may also define
  3 optional callbacks: `on_complete/1`, `on_success/1`, and `on_discard/1`.

  ## Defining an ObanBatch.Worker

  ObanBatch.Worker modules are defined by using `ObanBatch.Worker`. Jobs are enqueued to the batch by
  adding the the key `batch_id` to the args payload of any job, with the unique batch_id provided to
  `perform_with_batch/3` as the value.

  The following example demonstrates defining a worker module to use a batch, enqueue jobs
  asynchronously that belong to the batch, and define callbacks for when all jobs in the batch
  have run.

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

  Jobs enqueued in the batch may eneuque other jobs that belong to the batch simply by adding the batch_id
  to the args of any job.

  ## ObanBatch.Worker callbacks

  All batch callbacks are optional, and are guaranteed to only be executed once when the final job
  in the batch has finished running. All callbacks receive the batch_id as an argument.

  `on_complete` will get called when all jobs in the batch are in a finished state -- "completed" or "discarded.

  `on_success` will get called when all jobs in the batch are successful (have a "completed" state)

  `on_failure` will get called when all jobs in the batch are in a finished state and at least one has a "discarded" state.

  **Note** In the event any jobs belonging to a batch retires, the batch will not complete until all the retries are exhausted
  and all jobs are in a finished state.
  """

  @doc """
  The `perform_with_batch/3` function is called to execute a job that creates a batch.

  Since this is a wrapper around Oban.Worker.perform, `perform_with_batch/3` function should also return `:ok`
  or a success tuple. When the return is an error tuple, an uncaught exception or a throw then the error is
  recorded and the job may be retried if there are any attempts remaining.

  Note that the `args` map passed to `perform_with_batch/3` will _always_ have string keys, regardless of the
  key type when the job was enqueued. The `args` are stored as `jsonb` in PostgreSQL and the
  serialization process automatically stringifies all keys.
  """
  @callback perform_with_batch(args :: any, batch_id :: any, job :: any) :: any

  @doc """
  An optional callback that will execute when all jobs in the batch are in a finished state
  """
  @callback on_complete(batch_id :: any) :: any

  @doc """
  An optional callback that will execute when all jobs in the batch are successful
  """
  @callback on_success(batch_id :: any) :: any

  @doc """
  An optional callback that will execute when all jobs in the batch are in a finsihed state
  and there's at least one job whose state is "discarded"
  """
  @callback on_discard(batch_id :: any) :: any

  defmacro __using__(opts) do
    quote location: :keep do
      alias ObanBatch.Manager
      alias Ecto.UUID

      use Oban.Worker, unquote(opts)

      @behaviour ObanBatch.Worker

      @impl ObanBatch.Worker
      def on_complete(_) do
      end

      @impl ObanBatch.Worker
      def on_success(_) do
      end

      @impl ObanBatch.Worker
      def on_discard(_) do
      end

      @impl Oban.Worker
      def perform(args, job = %{id: job_id}) do
        {:ok, batch_id} = UUID.bingenerate() |> UUID.cast()

        Manager.attach_batch_listener(batch_id, __MODULE__, job_id)

        # Call this in a roundabout way so that the behavior
        # will work if the implementing module doesn't include
        # the callback
        apply(__MODULE__, :perform_with_batch, [args, batch_id, job])
      end

      defoverridable ObanBatch.Worker
    end
  end
end
