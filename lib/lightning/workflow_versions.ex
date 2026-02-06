defmodule Lightning.WorkflowVersions do
  @moduledoc """
  Provenance + comparison helpers for workflow heads.

  - Persists append-only rows in `workflow_versions` with deterministic ordering
    by `(inserted_at, id)`.
  - `record_version/3` is **idempotent** and **concurrency-safe** (squashes
    consecutive versions with the same source).
  - `history_for/1` and `latest_hash/1` query the table with deterministic ordering.
  - `classify/2` and `classify_with_delta/2` compare two histories (same/ahead/diverged).

  Validation & invariants:
  - `hash` must match `^[a-f0-9]{12}$`; `source` must be `"app"` or `"cli"`.

  Designed for fast diffs and consistent "latest head" lookups.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Lightning.Repo
  alias Lightning.Validators.Hex
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.WorkflowVersion

  @type hash :: String.t()

  @sources ~w(app cli)

  @doc """
  Records a **single** workflow head `hash` with provenance.

  This operation is **idempotent** and **concurrency-safe**:
  - If the latest version has the same source, it squashes (replaces) it
  - If the hash+source already exists, it does nothing
  - Otherwise, it inserts a new row

  ## Parameters
    * `workflow` — the workflow owning the history
    * `hash` — 12-char lowercase hex (e.g., `"deadbeefcafe"`)
    * `source` — `"app"` or `"cli"` (defaults to `"app"`)

  ## Returns
    * `{:ok, %Workflow{}}` — workflow (unchanged)
    * `{:error, reason}` — database error

  ## Examples

      iex> WorkflowVersions.record_version(wf, "deadbeefcafe", "app")
      {:ok, %Workflow{}}

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
        {:ok, latest_version(workflow.id)}
      end)
      |> Multi.run(:is_duplicate, fn _repo, %{latest_version: latest_version} ->
        {:ok,
         is_map(latest_version) and latest_version.hash == hash and
           latest_version.source == source}
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
      |> maybe_insert_new_version(
        WorkflowVersion.changeset(%WorkflowVersion{}, %{
          workflow_id: workflow.id,
          hash: hash,
          source: source
        })
      )
      |> maybe_delete_current_latest()
      |> Repo.transaction()
      |> case do
        {:ok, _} -> {:ok, workflow}
        {:error, _op, reason, _} -> {:error, reason}
      end
    else
      false -> {:error, :invalid_input}
    end
  end

  defp maybe_insert_new_version(multi, changeset) do
    Multi.run(
      multi,
      :new_version,
      fn repo, %{is_duplicate: is_duplicate} ->
        if is_duplicate do
          {:ok, nil}
        else
          repo.insert(changeset)
        end
      end
    )
  end

  defp maybe_delete_current_latest(multi) do
    Multi.run(
      multi,
      :delete_latest,
      fn repo, %{should_squash: should_squash, latest_version: latest_version} ->
        if should_squash do
          repo.delete(latest_version)
        else
          {:ok, nil}
        end
      end
    )
  end

  @doc """
  Returns the **ordered** history of heads for a workflow.

  Queries `workflow_versions` ordered by `inserted_at ASC, id ASC` to provide
  deterministic ordering for equal timestamps.

  ## Examples

      iex> WorkflowVersions.history_for(wf)
      ["app:a", "cli:b", "app:c"]
  """
  def history_for(%Workflow{id: id}) do
    from(v in WorkflowVersion,
      where: v.workflow_id == ^id,
      order_by: [asc: v.inserted_at, asc: v.id],
      select: fragment("? || ':' || ?", v.source, v.hash)
    )
    |> Repo.all()
  end

  @doc """
  Returns the **latest** head for a workflow (or `nil` if none).

  Queries `workflow_versions` with `ORDER BY inserted_at DESC, id DESC LIMIT 1`
  for deterministic results.

  ## Examples

      iex> WorkflowVersions.latest_hash(wf)
      "app:b"

      iex> WorkflowVersions.latest_hash(wf_without_versions)
      nil
  """
  @spec latest_hash(Workflow.t()) :: hash | nil
  def latest_hash(%Workflow{} = wf) do
    from(v in WorkflowVersion,
      where: v.workflow_id == ^wf.id,
      order_by: [desc: v.inserted_at, desc: v.id],
      limit: 1,
      select: fragment("? || ':' || ?", v.source, v.hash)
    )
    |> Repo.one()
  end

  defp latest_version(workflow_id) do
    from(v in WorkflowVersion,
      where: v.workflow_id == ^workflow_id,
      order_by: [desc: v.inserted_at, desc: v.id],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Generates a deterministic hash for a workflow based on its structure.

  Algorithm:
  - Create a list
  - Add the workflow name to the start of the list
  - For each node (trigger, job and edge) in a consistent order
    - Take only the relevant fields (e.g., name, body, adaptor)
    - Sort by field name (for consistency)
    - Add only the field VALUES to the list (keys are excluded)
    - Numeric values (e.g., positions) are rounded up to integers
  - Join the list into a string, no separator
  - Hash the string with SHA 256
  - Truncate the resulting string to 12 characters

  ## Parameters
    * `workflow` — the workflow struct to hash

  ## Returns
    * A 12-character lowercase hex string

  ## Examples

      iex> WorkflowVersions.generate_hash(workflow)
      "a1b2c3d4e5f6"
  """
  @spec generate_hash(Workflow.t() | map()) :: binary()
  def generate_hash(%Workflow{} = workflow) do
    workflow = Repo.preload(workflow, [:jobs, :edges, :triggers])

    workflow
    |> Map.from_struct()
    |> generate_hash()
  end

  def generate_hash(%{} = workflow) do
    workflow_keys = [:name, :positions]

    job_keys = [
      :name,
      :adaptor,
      :keychain_credential_id,
      :project_credential_id,
      :body
    ]

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
      |> Enum.map(fn {_k, v} -> serialize_value(v) end)

    triggers_hash_list =
      workflow.triggers
      |> Enum.sort_by(& &1.type)
      |> Enum.reduce([], fn trigger, acc ->
        hash_list =
          trigger
          |> Map.take(trigger_keys)
          |> Enum.sort_by(fn {k, _v} -> k end)
          |> Enum.map(fn {_k, v} -> serialize_value(v) end)

        acc ++ hash_list
      end)

    jobs_hash_list =
      workflow.jobs
      |> Enum.sort_by(fn job -> String.downcase(job.name || "") end)
      |> Enum.reduce([], fn job, acc ->
        hash_list =
          job
          |> Map.take(job_keys)
          |> Enum.sort_by(fn {k, _v} -> k end)
          |> Enum.map(fn {_k, v} -> serialize_value(v) end)

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
          |> Enum.map(fn {_k, v} -> serialize_value(v) end)

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

  defp serialize_value(val) when is_map(val) do
    val
    |> round_numeric_values()
    |> Jason.encode!()
  end

  defp serialize_value(val) when is_number(val), do: val |> ceil() |> to_string()
  defp serialize_value(val), do: to_string(val)

  defp round_numeric_values(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, round_numeric_values(v)} end)
  end

  defp round_numeric_values(val) when is_number(val), do: ceil(val)
  defp round_numeric_values(val), do: val

  defp edge_name(edge, workflow) do
    source_name =
      cond do
        Map.get(edge, :source_trigger_id) ->
          trigger =
            Enum.find(workflow.triggers, fn t ->
              t.id == edge.source_trigger_id
            end)

          trigger && trigger.type

        Map.get(edge, :source_job_id) ->
          job = Enum.find(workflow.jobs, fn j -> j.id == edge.source_job_id end)
          job && job.name

        true ->
          nil
      end

    target_job = Enum.find(workflow.jobs, fn j -> j.id == edge.target_job_id end)
    target_name = target_job && target_job.name

    "#{source_name}-#{target_name}"
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

  defp common_prefix_len(a, b),
    do: Enum.zip(a, b) |> Enum.take_while(fn {x, y} -> x == y end) |> length()
end
