defmodule ObanBatch.ManagerTest do
  use ExUnit.Case, async: true
  use ObanBatch.DataCase

  alias ObanBatch.Manager
  alias ObanBatch.State
  alias ObanBatch.Test.Repo
  alias Ecto.UUID

  def detatch_telemetry_handlers(_) do
    [[:oban, :success], [:oban, :failure]]
    |> Enum.each(fn event_name ->
      :telemetry.list_handlers(event_name)
      |> Enum.each(fn %{id: id} ->
        :telemetry.detach(id)
      end)
    end)
  end

  def uuid() do
    UUID.bingenerate() |> UUID.cast!()
  end

  setup :detatch_telemetry_handlers

  setup_all do
    [
      parent_job_id: 1,
      child_job_id: 2
    ]
  end

  def setup_test(batch_id, job_state) do
    %Oban.Job{
      state: job_state,
      args: %{batch_id: batch_id},
      worker: "TestWorker"
    }
    |> Repo.insert()

    State.start_batch(batch_id)
  end

  defmodule TestBatchWorker do
    def test_handler(_, _, _, _) do
    end

    def on_complete(_) do
      send(self(), "On complete callback ran")
    end

    def on_success(_) do
      send(self(), "On success callback ran")
    end

    def on_discard(_) do
      send(self(), "On discard callback ran")
    end
  end

  describe "attach_batch_listener/2" do
    test "side effects: it will attach telemetry listeners", context do
      # note: this must be cast to a variable rather than put directly into the pattern matching
      # https://github.com/elixir-lang/elixir/issues/5649#issuecomment-272259876
      expected_listener = &Manager.handle_job_run/4
      batch_id = uuid()
      job_id = context[:parent_job_id]

      Manager.attach_batch_listener(batch_id, __MODULE__, job_id)

      assert [
               %{
                 function: ^expected_listener,
                 config: %{batch_id: ^batch_id, module: __MODULE__, parent_job_id: job_id}
               }
             ] = :telemetry.list_handlers([:oban, :success])

      assert [
               %{
                 function: ^expected_listener,
                 config: %{batch_id: ^batch_id, module: __MODULE__, parent_job_id: job_id}
               }
             ] = :telemetry.list_handlers([:oban, :failure])
    end

    test "side effects: it will add batch state to the batch agent", context do
      batch_id = uuid()
      job_id = context[:parent_job_id]
      Manager.attach_batch_listener(batch_id, __MODULE__, job_id)

      assert true =
               Agent.get(State, fn %{^batch_id => in_progress} ->
                 in_progress
               end)
    end
  end

  describe "handle_job_run/4" do
    test "when there's no batch_id in the job args it will be a no op", context do
      job = %{id: context[:child_job_id], args: %{"a" => "b"}}
      assert nil == Manager.handle_job_run(nil, nil, job, nil)
    end

    test "when the job batch_id doesn't match the given batch_id it will be a no op", context do
      assert nil ==
               Manager.handle_job_run(
                 nil,
                 nil,
                 %{id: context[:child_job_id], args: %{"batch_id" => "this_batch_id"}},
                 %{
                   batch_id: "that_batch_id",
                   module: __MODULE__,
                   parent_job_id: context[:parent_job_id]
                 }
               )
    end

    test "when not all jobs have finished the callbacks will not execute", context do
      batch_id = uuid()

      setup_test(batch_id, "executing")

      Manager.handle_job_run(
        nil,
        nil,
        %{id: context[:child_job_id], args: %{"batch_id" => batch_id}},
        %{batch_id: batch_id, module: TestBatchWorker, parent_job_id: context[:parent_job_id]}
      )

      refute_received "On complete callback ran"
      refute_received "On success callback ran"
      refute_received "On discard callback ran"
    end

    test "when the batch is not in progress the callbacks will not execute", context do
      batch_id = uuid()

      setup_test(batch_id, "completed")

      # Mark the batch as no longer in progress
      State.get_or_update_batch_in_progress(batch_id)

      Manager.handle_job_run(
        nil,
        nil,
        %{id: context[:child_job_id], args: %{"batch_id" => batch_id}},
        %{batch_id: batch_id, module: TestBatchWorker, parent_job_id: context[:parent_job_id]}
      )

      refute_received "On complete callback ran"
      refute_received "On success callback ran"
      refute_received "On discard callback ran"
    end

    test "when all jobs have finished with success and the batch is in progress the callbacks will execute",
         context do
      batch_id = uuid()

      setup_test(batch_id, "completed")

      Manager.handle_job_run(
        nil,
        nil,
        %{id: context[:child_job_id], args: %{"batch_id" => batch_id}},
        %{batch_id: batch_id, module: TestBatchWorker, parent_job_id: context[:parent_job_id]}
      )

      assert_received "On complete callback ran"
      assert_received "On success callback ran"
    end

    test "when all jobs have finished with a discard and the batch is in progress the callbacks will execute" do
      batch_id = uuid()

      setup_test(batch_id, "discarded")

      Manager.handle_job_run(
        nil,
        nil,
        %{id: 2, args: %{"batch_id" => batch_id}},
        %{batch_id: batch_id, module: TestBatchWorker, parent_job_id: 1}
      )

      assert_received "On complete callback ran"
      assert_received "On discard callback ran"
    end

    test "the attached listener will get detached", context do
      batch_id = uuid()

      setup_test(batch_id, "completed")

      :telemetry.attach_many(
        "oban-batch-event-#{batch_id}",
        [[:oban, :success], [:oban, :failure]],
        &TestBatchWorker.test_handler/4,
        nil
      )

      Manager.handle_job_run(
        nil,
        nil,
        %{id: context[:child_job_id], args: %{"batch_id" => batch_id}},
        %{batch_id: batch_id, module: TestBatchWorker, parent_job_id: context[:parent_job_id]}
      )

      assert [] == :telemetry.list_handlers([:oban, :success])
      assert [] == :telemetry.list_handlers([:oban, :failure])
    end

    test "when the jobs in the batch finish before the job queueing them the callbacks will not execute" do
      batch_id = uuid()

      {:ok, parent_job} =
        %Oban.Job{
          state: "executing",
          args: %{},
          worker: "TestWorker"
        }
        |> Repo.insert()

      {:ok, child_job} =
        %Oban.Job{
          state: "completed",
          args: %{batch_id: batch_id},
          worker: "TestWorker"
        }
        |> Repo.insert()

      State.start_batch(batch_id)

      Manager.handle_job_run(
        nil,
        nil,
        %{id: child_job.id, args: %{"batch_id" => batch_id}},
        %{batch_id: batch_id, module: TestBatchWorker, parent_job_id: parent_job.id}
      )

      refute_received "On complete callback ran"
      refute_received "On success callback ran"
      refute_received "On discard callback ran"
    end

    test "when the jobs in the batch and the enqueueing job has finished the callbacks will execute" do
      batch_id = uuid()

      {:ok, parent_job} =
        %Oban.Job{
          state: "completed",
          args: %{},
          worker: "TestWorker"
        }
        |> Repo.insert()

      {:ok, child_job} =
        %Oban.Job{
          state: "completed",
          args: %{batch_id: batch_id},
          worker: "TestWorker"
        }
        |> Repo.insert()

      State.start_batch(batch_id)

      Manager.handle_job_run(
        nil,
        nil,
        %{id: child_job.id, args: %{"batch_id" => batch_id}},
        %{batch_id: batch_id, module: TestBatchWorker, parent_job_id: parent_job.id}
      )

      assert_received "On complete callback ran"
      assert_received "On success callback ran"
    end
  end
end
