defmodule Lightning.Invocation.DeleteOrphanedSteps do
  @moduledoc """
  Deletes steps that no run links to.

  Steps are always written together with their `run_steps` row, so a step
  without one can't be reached from any run or work order. Such steps stop a
  deleted workflow from being purged, because `steps.snapshot_id` restricts
  deleting the snapshot.

  It walks the whole steps table in primary key order, a window of step ids at
  a time, and deletes the orphans in each window in small chunks. Each deleted
  step cascades into every `log_lines` partition, which costs about 100ms per
  step on a cold cache.

  Each job works for about ten seconds, then enqueues a successor carrying the
  last finished window's id as `after_id`, and the walk ends when a window comes
  back empty. Jobs are kept short so that one running during a deploy finishes
  inside the shutdown window Kubernetes allows before force-killing the node,
  with its successor already queued. A retried job repeats at most one window,
  which is harmless.

  It runs on the `maintenance` queue, which only versions that have this module
  poll, so a node still running an older release never picks it up mid-deploy.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 5

  import Ecto.Query

  alias Lightning.Invocation.Step
  alias Lightning.Repo
  alias Lightning.RunStep

  @window 1_000
  @chunk_size 50
  @budget_ms 10_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    deadline = System.monotonic_time(:millisecond) + @budget_ms

    walk(args["after_id"], deadline)
  end

  defp walk(after_id, deadline) do
    case next_window(after_id) do
      [] ->
        :ok

      window ->
        {last_id, _orphan?} = List.last(window)

        orphan_ids = for {id, true} <- window, do: id

        case delete_in_chunks(orphan_ids, deadline) do
          :done ->
            if out_of_time?(deadline),
              do: continue_later(last_id),
              else: walk(last_id, deadline)

          :out_of_time ->
            continue_later(after_id)
        end
    end
  end

  # The budget is checked after a chunk, never before, so a job always gets
  # through at least one chunk and the chain can't stall re-reading a window.
  defp delete_in_chunks([], _deadline), do: :done

  defp delete_in_chunks(ids, deadline) do
    {chunk, rest} = Enum.split(ids, @chunk_size)

    Repo.delete_all(where(orphaned_steps(), [s], s.id in ^chunk))

    cond do
      rest == [] -> :done
      out_of_time?(deadline) -> :out_of_time
      true -> delete_in_chunks(rest, deadline)
    end
  end

  defp continue_later(after_id) do
    {:ok, _job} =
      Oban.insert(Lightning.Oban, new(%{"after_id" => after_id}))

    :ok
  end

  defp out_of_time?(deadline),
    do: System.monotonic_time(:millisecond) >= deadline

  defp next_window(after_id) do
    from(s in Step,
      as: :step,
      order_by: s.id,
      limit: @window,
      select: {s.id, not exists(linked_runs())}
    )
    |> after_cursor(after_id)
    |> Repo.all()
  end

  defp after_cursor(query, nil), do: query
  defp after_cursor(query, after_id), do: where(query, [s], s.id > ^after_id)

  defp orphaned_steps do
    from(s in Step, as: :step, where: not exists(linked_runs()))
  end

  defp linked_runs do
    from(rs in RunStep, where: rs.step_id == parent_as(:step).id, select: 1)
  end
end
