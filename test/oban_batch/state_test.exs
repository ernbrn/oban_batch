defmodule ObanBatch.StateTest do
  alias ObanBatch.State
  use ExUnit.Case, async: false

  def uuid() do
    Ecto.UUID.bingenerate() |> Ecto.UUID.cast!()
  end

  describe "start_batch/1" do
    test "it will add the given batch_id to the map with an true value" do
      batch_id = uuid()
      assert :ok == State.start_batch(batch_id)
      assert true == Agent.get(State, fn %{^batch_id => in_progress} -> in_progress end)
    end
  end

  describe "get_or_update_batch_in_progress/1" do
    test "when the batch is in progress it will update it to not in progress" do
      batch_id = uuid()

      State.start_batch(batch_id)

      assert true == State.get_or_update_batch_in_progress(batch_id)
      assert false == Agent.get(State, fn %{^batch_id => in_progress} -> in_progress end)
    end

    test "when the batch is not in progress" do
      batch_id = uuid()

      Agent.update(State, fn state_map ->
        Map.put(state_map, batch_id, false)
      end)

      assert false == State.get_or_update_batch_in_progress(batch_id)
    end
  end
end
