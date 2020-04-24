defmodule ObanBatch.State do
  @moduledoc """
  A suite of functions that keep the in_progress state of all batches for the application.
  Each unique batch id is the key, and an in_progress boolean is the value.

  Example state:

  %{
    "a67dc066-f4bb-4a6d-acd3-63dbab149e60" => true,
    "bc2de5e2-8832-4990-84b9-6688945685c4" => false
  }
  """
  use Agent

  @doc """
  Starts the agent with empty state. Called by the supervisor.
  """
  def start_link(_) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Adds a batch id to the state with an in_progress value of true
  """
  def start_batch(batch_id) do
    Agent.update(__MODULE__, fn state_map ->
      Map.put(state_map, batch_id, true)
    end)
  end

  @doc """
  Returns the in_progress state of the given batch_id. If in_progress is true
  it will update it to false in the same operation to ensure only one operation
  may ever get a true value.
  """
  def get_or_update_batch_in_progress(batch_id) do
    Agent.get_and_update(__MODULE__, fn state_map = %{^batch_id => in_progress} ->
      if in_progress do
        {in_progress, Map.update!(state_map, batch_id, fn _ -> false end)}
      else
        {in_progress, state_map}
      end
    end)
  end
end
