defmodule Lightning.Workflows.WorkflowReleases do
  @moduledoc """
  Records and reads `Lightning.Workflows.WorkflowRelease` rows.

  A release is recorded at each go-live and promote, in the same transaction as
  the snapshot it points at, and numbered `max(existing) + 1` per workflow.

  That numbering is safe only because callers record a release exclusively when
  the save captured a snapshot: capturing one updates the workflow row, so the
  optimistic lock serialises concurrent publishes. The
  `(workflow_id, version_number)` unique index is the backstop.
  """
  import Ecto.Query

  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.WorkflowRelease

  @doc """
  Inserts a single release with the next sequential `version_number`, using the
  given `repo` so it participates in the surrounding transaction.
  """
  @spec insert_release(Ecto.Repo.t(), map()) ::
          {:ok, WorkflowRelease.t()} | {:error, Ecto.Changeset.t()}
  def insert_release(repo, attrs) do
    attrs = Map.put(attrs, :version_number, next_version_number(repo, attrs))

    %WorkflowRelease{}
    |> WorkflowRelease.changeset(attrs)
    |> repo.insert()
  end

  @doc """
  Returns the next sequential version number for the workflow, computed against
  the given `repo` inside the current transaction.
  """
  @spec next_version_number(Ecto.Repo.t(), map()) :: pos_integer()
  def next_version_number(repo, %{workflow_id: workflow_id}) do
    max =
      from(r in WorkflowRelease,
        where: r.workflow_id == ^workflow_id,
        select: max(r.version_number)
      )
      |> repo.one()

    (max || 0) + 1
  end

  @doc """
  Lists a workflow's releases newest first, preloaded with the snapshot and the
  provenance associations the version list renders.
  """
  @spec list_for_workflow(Workflow.t() | Ecto.UUID.t()) :: [WorkflowRelease.t()]
  def list_for_workflow(workflow_or_id) do
    workflow_id = workflow_id(workflow_or_id)

    from(r in WorkflowRelease,
      where: r.workflow_id == ^workflow_id,
      order_by: [desc: r.version_number],
      preload: [:snapshot, :published_by, :source_project]
    )
    |> Lightning.Repo.all()
  end

  @doc """
  Fetches the release published as `version_number` for the workflow, preloaded
  with its snapshot so the caller can resolve the pinned content.

  `version_number` is the human version the UI shows as vN and the value `?release=`
  carries. Returns nil when the workflow has no release with that number (a
  hand-typed number, or an old lock_version that was never published).
  """
  @spec get_by_version_number(Workflow.t() | Ecto.UUID.t(), integer()) ::
          WorkflowRelease.t() | nil
  def get_by_version_number(workflow_or_id, version_number) do
    workflow_id = workflow_id(workflow_or_id)

    from(r in WorkflowRelease,
      where:
        r.workflow_id == ^workflow_id and r.version_number == ^version_number,
      preload: [:snapshot]
    )
    |> Lightning.Repo.one()
  end

  @doc """
  Maps each released snapshot `lock_version` to the `version_number` it was
  published as.

  This is what attributes a run to a release: a run carries its snapshot's
  `lock_version`, and `Map.get/2` gives `nil` for one that was never released.
  Where two releases share a `lock_version` the newest wins.
  """
  @spec version_numbers_by_lock_version(Workflow.t() | Ecto.UUID.t()) ::
          %{integer() => pos_integer()}
  def version_numbers_by_lock_version(workflow_or_id) do
    workflow_id = workflow_id(workflow_or_id)

    from(r in WorkflowRelease,
      join: s in assoc(r, :snapshot),
      where: r.workflow_id == ^workflow_id,
      group_by: s.lock_version,
      select: {s.lock_version, max(r.version_number)}
    )
    |> Lightning.Repo.all()
    |> Map.new()
  end

  defp workflow_id(%Workflow{id: id}), do: id
  defp workflow_id(id) when is_binary(id), do: id
end
