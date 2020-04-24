defmodule ObanBatch.Manager do
  @moduledoc """
  A suite of functions that manage all aspects of starting a batch and executing
  the callbacks when a batch has compelted.
  """
  alias ObanBatch.State

  import Ecto.Query, warn: false

  @completed_status "completed"
  @discarded_status "discarded"
  @finished_statuses [@completed_status, @discarded_status]

  @doc """
  Attaches a unique listener to listen for all jobs that
  have finished (completed or discarded). Accepts a batch_id
  and the module that houses the callback functions that should
  be executed upon batch completion
  """
  def attach_batch_listener(batch_id, module, parent_job_id) do
    :telemetry.attach_many(
      handler_id(batch_id),
      [[:oban, :success], [:oban, :failure]],
      &__MODULE__.handle_job_run/4,
      %{batch_id: batch_id, module: module, parent_job_id: parent_job_id}
    )

    State.start_batch(batch_id)
  end

  @doc """
  The handler function for the oban job event listener. Will only execute for jobs
  that contain the batch_id given when attaching the listener, or the job that initiated the batch.

  Upon any job completion (success or discard), a query will be executed to see if all jobs in the
  batch have completed (including the initiating job) and if the batch is still in progress.
  If all criteria is satisfied, the callbacks for the given module will be executed and the listener will be detached.
  """
  def handle_job_run(
        _message,
        _timing,
        %{args: %{"batch_id" => job_batch_id}},
        %{batch_id: batch_id, module: module, parent_job_id: parent_job_id}
      )
      when job_batch_id == batch_id do
    check_for_batch_completion(batch_id, parent_job_id, module)
  end

  def handle_job_run(
        _message,
        _timing,
        %{id: finished_id},
        %{batch_id: batch_id, module: module, parent_job_id: parent_job_id}
      )
      when finished_id == parent_job_id do
    check_for_batch_completion(batch_id, parent_job_id, module)
  end

  @doc """
  No op for any events we don't care to act on
  """
  def handle_job_run(_, _, _, _) do
  end

  # private

  defp check_for_batch_completion(batch_id, parent_job_id, module) do
    if all_jobs_finished?(batch_id, parent_job_id) &&
         State.get_or_update_batch_in_progress(batch_id) do
      execute_callbacks(batch_id, module)
      clean_up(batch_id)
    end
  end

  defp all_jobs_finished?(batch_id, parent_job_id) do
    Oban.Job
    |> where([job], fragment("?->>'batch_id' = ?", job.args, ^batch_id))
    |> or_where([job], job.id == ^parent_job_id)
    |> where([job], job.state not in @finished_statuses)
    |> select([job], job.id)
    |> Oban.config().repo.all()
    |> Enum.empty?()
  end

  defp execute_callbacks(batch_id, module) do
    apply(module, :on_complete, [batch_id])

    if jobs_discarded?(batch_id) do
      apply(module, :on_discard, [batch_id])
    else
      apply(module, :on_success, [batch_id])
    end
  end

  defp clean_up(batch_id) do
    :telemetry.detach(handler_id(batch_id))
  end

  defp batch_statuses(batch_id) do
    Oban.Job
    |> where([job], job.state in @finished_statuses)
    |> where([job], fragment("?->>'batch_id' = ?", job.args, ^batch_id))
    |> select([job], job.state)
    |> Oban.config().repo.all()
  end

  defp jobs_discarded?(batch_id) do
    Enum.member?(batch_statuses(batch_id), @discarded_status)
  end

  defp handler_id(batch_id) do
    "oban-batch-event-#{batch_id}"
  end
end
