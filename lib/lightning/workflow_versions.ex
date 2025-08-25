defmodule Lightning.WorkflowVersions do
  @moduledoc """
  Lightweight provenance & compare helpers for workflow histories.

  - Persists rows in `workflow_versions` (append-only, idempotent)
  - Keeps `workflows.version_history` in sync for fast comparisons
  - Classifies histories (same/ahead/behind/diverged) with deltas
  """
  import Ecto.Query
  alias Ecto.Changeset
  alias Ecto.Multi
  alias Lightning.Repo
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.WorkflowVersion

  # 12 hex chars like "a1b2c3d4e5f6"
  @type hash :: String.t()

  @hash_regex ~r/^[a-f0-9]{12}$/
  @sources ~w(app cli)

  @doc """
  Record a single version hash for a workflow.

  Atomically:
    * inserts a row in `workflow_versions` (idempotent via `ON CONFLICT DO NOTHING`)
    * appends the hash to `workflows.version_history` (guarded; no dup; concurrency-safe)

  Returns `{:ok, %Workflow{}}` on success.
  """
  @spec record_version(Workflow.t(), hash, String.t()) ::
          {:ok, Workflow.t()} | {:error, term()}
  def record_version(%Workflow{id: id}, hash, source \\ "app")
      when is_binary(hash) and is_binary(source) do
    with true <- Regex.match?(@hash_regex, hash),
         true <- source in @sources do
      Multi.new()
      |> Multi.insert(
        :row,
        WorkflowVersion.changeset(%WorkflowVersion{}, %{
          workflow_id: id,
          hash: hash,
          source: source
        }),
        on_conflict: :nothing,
        conflict_target: [:workflow_id, :hash]
      )
      |> Multi.run(:append_history, fn repo, _ ->
        wf =
          from(w in Workflow, where: w.id == ^id, lock: "FOR UPDATE")
          |> repo.one!()

        new_hist = append_if_missing(wf.version_history || [], hash)

        if new_hist == (wf.version_history || []) do
          {:ok, wf}
        else
          wf
          |> Changeset.change(version_history: new_hist)
          |> repo.update()
        end
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{append_history: updated}} -> {:ok, updated}
        {:error, _op, reason, _} -> {:error, reason}
      end
    else
      false -> {:error, :invalid_input}
    end
  end

  @doc """
  Bulk variant. Inserts many hashes and appends them to `version_history`
  in order, without duplicates. Returns `{:ok, workflow, inserted_count}`.
  """
  @spec record_versions(Workflow.t(), [hash], String.t()) ::
          {:ok, Workflow.t(), non_neg_integer()} | {:error, term()}
  def record_versions(%Workflow{id: id}, hashes, source \\ "app")
      when is_list(hashes) do
    if valid_input?(hashes, source) do
      do_record_versions(id, Enum.uniq(hashes), source)
    else
      {:error, :invalid_input}
    end
  end

  defp valid_input?(hashes, source) do
    Enum.all?(hashes, &Regex.match?(@hash_regex, &1)) and source in @sources
  end

  defp do_record_versions(id, hashes, source) do
    now = DateTime.utc_now(:microsecond)
    rows = build_rows(id, hashes, source, now)

    Multi.new()
    |> Multi.insert_all(
      :rows,
      WorkflowVersion,
      rows,
      on_conflict: :nothing,
      conflict_target: [:workflow_id, :hash]
    )
    |> Multi.run(:append_history, fn repo, _ ->
      append_history(repo, id, hashes)
    end)
    |> Repo.transaction()
    |> handle_bulk_txn()
  end

  defp build_rows(id, hashes, source, now) do
    for h <- hashes,
        do: %{workflow_id: id, hash: h, source: source, inserted_at: now}
  end

  defp append_history(repo, id, hashes) do
    wf =
      from(w in Workflow, where: w.id == ^id, lock: "FOR UPDATE")
      |> repo.one!()

    new_hist =
      Enum.reduce(hashes, wf.version_history || [], fn h, acc ->
        append_if_missing(acc, h)
      end)

    if new_hist == (wf.version_history || []) do
      {:ok, wf}
    else
      wf |> Changeset.change(version_history: new_hist) |> repo.update()
    end
  end

  defp handle_bulk_txn(
         {:ok, %{rows: {inserted_count, _}, append_history: updated}}
       ),
       do: {:ok, updated, inserted_count}

  defp handle_bulk_txn({:error, _op, reason, _}),
    do: {:error, reason}

  @doc """
  Returns the ordered history of hashes for a workflow.

  If the `version_history` array is nil/empty, falls back to the table
  ordered by `inserted_at, id` for determinism.
  """
  def history_for(%Workflow{version_history: arr})
      when is_list(arr) and arr != [],
      do: arr

  def history_for(%Workflow{id: id}) do
    from(v in WorkflowVersion,
      where: v.workflow_id == ^id,
      order_by: [asc: v.inserted_at, asc: v.id],
      select: v.hash
    )
    |> Repo.all()
  end

  @doc """
  Returns the latest hash for a workflow (deterministic).

  Uses `version_history` when present; otherwise queries the versions table with
  `ORDER BY inserted_at DESC, id DESC`.
  """
  @spec latest_hash(Workflow.t()) :: hash | nil
  def latest_hash(%Workflow{} = wf) do
    case wf.version_history do
      list when is_list(list) and list != [] ->
        List.last(list)

      _ ->
        from(v in WorkflowVersion,
          where: v.workflow_id == ^wf.id,
          order_by: [desc: v.inserted_at, desc: v.id],
          limit: 1,
          select: v.hash
        )
        |> Repo.one()
    end
  end

  @doc """
  Rebuilds the `version_history` array from `workflow_versions` and saves it.
  Useful for maintenance/migrations.
  """
  @spec reconcile_history!(Workflow.t()) :: Workflow.t()
  def reconcile_history!(%Workflow{id: id} = wf) do
    arr = history_for(%Workflow{id: id, version_history: []})

    wf
    |> Changeset.change(version_history: arr)
    |> Repo.update!()
  end

  @doc """
  Classify two histories (left vs right) with delta:

    * `{:same, 0}`
    * `{:ahead, :right, n}`  – right extends left by `n`
    * `{:ahead, :left,  n}`  – left  extends right by `n`
    * `{:diverged, k}`       – diverged after `k` common items
  """
  @spec classify_with_delta([hash], [hash]) ::
          {:same, 0}
          | {:ahead, :left, non_neg_integer()}
          | {:ahead, :right, non_neg_integer()}
          | {:diverged, non_neg_integer()}
  def classify_with_delta(left, right) do
    cpl = common_prefix_len(left, right)

    cond do
      cpl == length(left) and cpl == length(right) -> {:same, 0}
      cpl == length(left) -> {:ahead, :right, length(right) - cpl}
      cpl == length(right) -> {:ahead, :left, length(left) - cpl}
      true -> {:diverged, cpl}
    end
  end

  @doc """
  Simpler classification without deltas, if you only need the relation.
  """
  @spec classify([hash], [hash]) ::
          :same | {:ahead, :left} | {:ahead, :right} | :diverged
  def classify(left, right) do
    case classify_with_delta(left, right) do
      {:same, _} -> :same
      {:ahead, side, _} -> {:ahead, side}
      {:diverged, _} -> :diverged
    end
  end

  defp append_if_missing(list, hash),
    do: if(Enum.member?(list, hash), do: list, else: list ++ [hash])

  defp common_prefix_len(a, b),
    do: Enum.zip(a, b) |> Enum.take_while(fn {x, y} -> x == y end) |> length()
end
