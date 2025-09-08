defmodule Lightning.WorkflowVersions do
  @moduledoc """
  Provenance + comparison helpers for workflow heads.

  - Persists append-only rows in `workflow_versions` and maintains a materialized
    `workflows.version_history` array (12-char lowercase hex).
  - `record_version/3` and `record_versions/3` are **idempotent** (`ON CONFLICT DO NOTHING`)
    and **concurrency-safe** (row lock, append without dupes).
  - `history_for/1` and `latest_hash/1` read the array first; when empty they fall back
    to the table with deterministic ordering by `(inserted_at, id)`.
  - `reconcile_history!/1` rebuilds the array from provenance rows.
  - `classify/2` and `classify_with_delta/2` compare two histories (same/ahead/diverged).

  Validation & invariants:
  - `hash` must match `^[a-f0-9]{12}$`; `source` must be `"app"` or `"cli"`;
    `(workflow_id, hash)` is unique.

  Designed for fast diffs and consistent “latest head” lookups.
  """
  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi
  alias Lightning.Repo
  alias Lightning.Validators.Hex
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.WorkflowVersion

  @type hash :: String.t()

  @sources ~w(app cli)

  @doc """
  Records a **single** workflow head `hash` with provenance and keeps
  `workflows.version_history` in sync.

  This operation is **idempotent** and **concurrency-safe**:
  it inserts into `workflow_versions` with `ON CONFLICT DO NOTHING`, then
  locks the workflow row (`FOR UPDATE`) and appends `hash` to the array only
  if it is not already present.

  ## Parameters
    * `workflow` — the workflow owning the history
    * `hash` — 12-char lowercase hex (e.g., `"deadbeefcafe"`)
    * `source` — `"app"` or `"cli"` (defaults to `"app"`)

  ## Returns
    * `{:ok, %Workflow{}}` — workflow (possibly unchanged) with an updated
      `version_history` if a new `hash` was appended
    * `{:error, :invalid_input}` — when `hash`/`source` are invalid
    * `{:error, reason}` — database error

  ## Examples

      iex> WorkflowVersions.record_version(wf, "deadbeefcafe", "app")
      {:ok, %Workflow{version_history: [..., "deadbeefcafe"]}}

      iex> WorkflowVersions.record_version(wf, "NOT_HEX", "app")
      {:error, :invalid_input}
  """
  @spec record_version(Workflow.t(), hash, String.t()) ::
          {:ok, Workflow.t()} | {:error, term()}
  def record_version(%Workflow{} = workflow, hash, source \\ "app")
      when is_binary(hash) and is_binary(source) do
    with true <- Hex.valid?(hash),
         true <- source in @sources do
      Multi.new()
      |> Multi.run(:latest_version, fn _repo, _changes ->
        {:ok, latest_version(workflow)}
      end)
      |> Multi.run(:is_duplicate, fn _repo, %{latest_version: latest_version} ->
        {:ok, is_map(latest_version) && latest_version.hash == hash}
      end)
      |> Multi.run(
        :should_squash,
        fn _repo,
           %{is_duplicate: is_duplicate, latest_version: latest_version} ->
          {:ok,
           !is_duplicate && is_map(latest_version) &&
             latest_version.source == source}
        end
      )
      |> Multi.run(
        :new_version,
        fn repo, %{is_duplicate: is_duplicate} ->
          if is_duplicate do
            {:ok, nil}
          else
            %WorkflowVersion{}
            |> WorkflowVersion.changeset(%{
              workflow_id: workflow.id,
              hash: hash,
              source: source
            })
            |> repo.insert()
          end
        end
      )
      |> Multi.run(
        :delete_latest,
        fn repo,
           %{should_squash: should_squash, latest_version: latest_version} ->
          if should_squash do
            repo.delete(latest_version)
          else
            {:ok, nil}
          end
        end
      )
      |> Multi.run(
        :append_history,
        fn repo, %{new_version: new_version, delete_latest: deleted_version} ->
          wf =
            from(w in Workflow, where: w.id == ^workflow.id, lock: "FOR UPDATE")
            |> repo.one!()

          new_hist =
            (wf.version_history || [])
            |> then(fn history ->
              if deleted_version do
                Enum.reject(history, fn hash -> hash == deleted_version.hash end)
              else
                history
              end
            end)
            |> then(fn history ->
              if new_version do
                append_if_missing(history, hash)
              else
                history
              end
            end)

          if new_hist == (wf.version_history || []) do
            {:ok, wf}
          else
            wf
            |> Changeset.change(version_history: new_hist)
            |> repo.update()
          end
        end
      )
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
  Bulk record **many** heads at once and append them to `version_history`
  **in order**, skipping duplicates both in the input and in the database.

  Internally this:
  * de-dups the input list (preserving first appearance order),
  * `INSERT ... ON CONFLICT DO NOTHING` into `workflow_versions`, and
  * locks the workflow row and appends only missing hashes.

  The operation is **idempotent** and safe to call concurrently.

  ## Parameters
    * `workflow` — the workflow owning the history
    * `hashes` — list of 12-char lowercase hex strings
    * `source` — `"app"` or `"cli"` (defaults to `"app"`)

  ## Returns
    * `{:ok, %Workflow{}, inserted_count}` — number of **new** provenance rows
      actually written (0 if everything already existed)
    * `{:error, :invalid_input}` — when any hash or the source is invalid
    * `{:error, reason}` — database error

  ## Notes
  * Passing `[]` is allowed and returns `{:ok, workflow, 0}`.
  * Ordering of `version_history` matches the **input order** for newly appended hashes.

  ## Examples

      iex> WorkflowVersions.record_versions(wf, ~w(a1a1a1a1a1a1 b2b2b2b2b2b2), "cli")
      {:ok, %Workflow{}, 2}

      iex> WorkflowVersions.record_versions(wf, ["bad"], "app")
      {:error, :invalid_input}
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
    Enum.all?(hashes, &Hex.valid?/1) and source in @sources
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
  Returns the **ordered** history of heads for a workflow.

  If `workflow.version_history` is present and non-empty, that array is returned.
  Otherwise, the function falls back to `workflow_versions` ordered by
  `inserted_at ASC, id ASC` to provide deterministic ordering for equal timestamps.

  ## Examples

      iex> WorkflowVersions.history_for(%Workflow{version_history: ["a", "b"]})
      ["a", "b"]

      iex> WorkflowVersions.history_for(wf) # when array is empty/nil
      ["a", "b", "c"]
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
  Returns the **latest** head for a workflow (or `nil` if none).

  Uses `workflow.version_history` when populated (taking the last element).
  If empty/nil, reads from `workflow_versions` with
  `ORDER BY inserted_at DESC, id DESC LIMIT 1` for deterministic results.

  ## Examples

      iex> WorkflowVersions.latest_hash(%Workflow{version_history: ["a", "b"]})
      "b"

      iex> WorkflowVersions.latest_hash(wf_without_versions)
      nil
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

  defp latest_version(workflow) do
    from(v in WorkflowVersion,
      where: v.workflow_id == ^workflow.id,
      order_by: [desc: v.inserted_at, desc: v.id],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Rebuilds and **persists** `workflow.version_history` from provenance rows.

  This is useful for maintenance/migrations when the array drifts from the
  `workflow_versions` table. Ordering is `inserted_at ASC, id ASC`.

  ## Returns
    * `%Workflow{}` — updated workflow with a rebuilt `version_history`

  ## Examples

      iex> wf = WorkflowVersions.reconcile_history!(wf)
      %Workflow{version_history: [...]}
  """
  @spec reconcile_history!(Workflow.t()) :: Workflow.t()
  def reconcile_history!(%Workflow{id: id} = wf) do
    arr = history_for(%Workflow{id: id, version_history: []})

    wf
    |> Changeset.change(version_history: arr)
    |> Repo.update!()
  end

  @doc """
  Generates a deterministic hash for a workflow based on its structure.

  Algorithm:
  - Create a list
  - Add the workflow name to the start of the list
  - For each node (trigger, job and edge) in a consistent order
    - Get a sorted list of keys
    - Filter out ignored keys
    - Add each key and value to the list
  - Join the list into a string, no separator
  - Hash the list with SHA 256
  - Truncate the resulting string to 12 characters

  ## Parameters
    * `workflow` — the workflow struct to hash

  ## Returns
    * A 12-character lowercase hex string

  ## Examples

      iex> WorkflowVersions.generate_hash(workflow)
      "a1b2c3d4e5f6"
  """
  @spec generate_hash(Workflow.t()) :: binary()
  def generate_hash(%Workflow{} = workflow) do
    workflow = Repo.preload(workflow, [:jobs, :edges, :triggers])

    workflow_keys = [:name, :positions]
    job_keys = [:name, :adaptor, :project_credential_id, :body]
    trigger_keys = [:type, :cron_expression, :enabled]

    edge_keys = [
      :name,
      :condition_type,
      :condition_label,
      :condition_expression,
      :enabled
    ]

    workflow_hash_list =
      workflow
      |> Map.take(workflow_keys)
      |> Enum.sort_by(fn {k, _v} -> k end)
      |> Enum.flat_map(fn {k, v} ->
        [to_string(k), serialize_value(v)]
      end)

    triggers_hash_list =
      workflow.triggers
      |> Enum.sort_by(& &1.type)
      |> Enum.reduce([], fn trigger, acc ->
        hash_list =
          trigger
          |> Map.take(trigger_keys)
          |> Enum.sort_by(fn {k, _v} -> k end)
          |> Enum.flat_map(fn {k, v} ->
            [to_string(k), serialize_value(v)]
          end)

        acc ++ hash_list
      end)

    jobs_hash_list =
      workflow.jobs
      |> Enum.sort_by(& &1.name)
      |> Enum.reduce([], fn job, acc ->
        hash_list =
          job
          |> Map.take(job_keys)
          |> Enum.sort_by(fn {k, _v} -> k end)
          |> Enum.flat_map(fn {k, v} -> [to_string(k), serialize_value(v)] end)

        acc ++ hash_list
      end)

    # (sort by generated name: source-target)
    edges_hash_list =
      workflow.edges
      |> Enum.map(fn edge ->
        edge
        |> Map.take(edge_keys)
        |> Map.put(:name, edge_name(edge, workflow))
      end)
      |> Enum.sort_by(& &1.name)
      |> Enum.reduce([], fn edge, acc ->
        hash_list =
          edge
          |> Enum.sort_by(fn {k, _v} -> k end)
          |> Enum.flat_map(fn {k, v} -> [to_string(k), serialize_value(v)] end)

        acc ++ hash_list
      end)

    joined_data =
      Enum.join([
        workflow_hash_list,
        triggers_hash_list,
        jobs_hash_list,
        edges_hash_list
      ])

    :crypto.hash(:sha256, joined_data)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end

  defp serialize_value(val) when is_map(val), do: Jason.encode!(val)
  defp serialize_value(val), do: to_string(val)

  defp edge_name(edge, workflow) do
    source_name =
      cond do
        edge.source_trigger_id ->
          trigger =
            Enum.find(workflow.triggers, fn t ->
              t.id == edge.source_trigger_id
            end)

          trigger.type

        edge.source_job_id ->
          job = Enum.find(workflow.jobs, fn j -> j.id == edge.source_job_id end)
          job.name

        true ->
          nil
      end

    target_job = Enum.find(workflow.jobs, fn j -> j.id == edge.target_job_id end)

    "#{source_name}-#{target_job.name}"
  end

  @doc """
  Compares two histories and returns the relation **with a delta**.

  Possible results:
    * `{:same, 0}` — sequences are identical
    * `{:ahead, :right, n}` — `right` strictly extends `left` by `n` items
    * `{:ahead, :left,  n}` — `left`  strictly extends `right` by `n` items
    * `{:diverged, k}` — sequences share a common prefix of length `k`, then diverge

  ## Examples

      iex> WorkflowVersions.classify_with_delta(~w(a b), ~w(a b c d))
      {:ahead, :right, 2}

      iex> WorkflowVersions.classify_with_delta(~w(a b x), ~w(a b y))
      {:diverged, 2}
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
  Compares two histories and returns only the relation (no counts).

  Wrapper around `classify_with_delta/2`.

  ## Examples

      iex> WorkflowVersions.classify(~w(a b), ~w(a b))
      :same

      iex> WorkflowVersions.classify(~w(a b), ~w(a b c))
      {:ahead, :right}

      iex> WorkflowVersions.classify(~w(a x), ~w(a y))
      :diverged
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
