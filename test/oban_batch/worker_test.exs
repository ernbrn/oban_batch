defmodule ObanBatch.WorkerTest do
  use ExUnit.Case, async: true

  def detatch_telemetry_handlers(_) do
    [[:oban, :success], [:oban, :failure]]
    |> Enum.each(fn event_name ->
      :telemetry.list_handlers(event_name)
      |> Enum.each(fn %{id: id} ->
        :telemetry.detach(id)
      end)
    end)
  end

  setup :detatch_telemetry_handlers

  defmodule TestWorker do
    use ObanBatch.Worker

    def perform_with_batch(%{"a" => a, "b" => b}, _batch_id, _job), do: a + b
    def perform_with_batch(_args, batch_id, _job), do: batch_id
  end

  defmodule CallbackWorker do
    use ObanBatch.Worker

    def perform_with_batch(_, _, _) do
    end

    def on_complete(_) do
      "complete"
    end

    def on_success(_) do
      "success"
    end

    def on_discard(_) do
      "discard"
    end
  end

  describe "perform/2" do
    test "it will wrap perform_with_batch" do
      args = %{"a" => 2, "b" => 3}
      assert 5 == TestWorker.perform(args, %Oban.Job{args: args})
    end

    test "it will provide perform_with_batch a batch_id UUID" do
      assert {:ok, _info} = Ecto.UUID.dump(TestWorker.perform(%{}, %Oban.Job{}))
    end

    test "side effects: it will attach telemetry event listeners" do
      TestWorker.perform(%{}, %Oban.Job{})

      # note: this must be cast to a variable rather than put directly in the pattern matching
      # https://github.com/elixir-lang/elixir/issues/5649#issuecomment-272259876
      expected_listener = &ObanBatch.Manager.handle_job_run/4

      assert [%{function: ^expected_listener}] = :telemetry.list_handlers([:oban, :success])
      assert [%{function: ^expected_listener}] = :telemetry.list_handlers([:oban, :failure])
    end
  end

  describe "on_complete/1" do
    test "default implementation" do
      assert nil == TestWorker.on_complete("batch_id")
    end

    test "override implementation" do
      assert "complete" == CallbackWorker.on_complete("batch_id")
    end
  end

  describe "on_success/1" do
    test "default implementation" do
      assert nil == TestWorker.on_success("batch_id")
    end

    test "override implementation" do
      assert "success" == CallbackWorker.on_success("batch_id")
    end
  end

  describe "on_discard/1" do
    test "default implementation" do
      assert nil == TestWorker.on_discard("batch_id")
    end

    test "override implementation" do
      assert "discard" == CallbackWorker.on_discard("batch_id")
    end
  end
end
