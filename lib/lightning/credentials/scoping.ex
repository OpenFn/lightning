defmodule Lightning.Credentials.Scoping do
  @moduledoc """
  Verifies that credential references belong to the project that owns them.

  Given a project id and a list of credential references, returns the subset
  whose `project_credential` or `keychain_credential` belongs to a different
  project. Issues read-only queries with no side effects, so it composes inside
  a caller's transaction and observes read-your-writes.

  Existence is not this module's concern: ids that resolve to no row are not
  reported (the foreign-key constraint already covers non-existence). This
  function is about *scoping* only.
  """
  import Ecto.Query

  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Repo
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Workflow

  @type ref :: %{
          required(:key) => term(),
          optional(:label) => String.t() | nil,
          optional(:project_credential_id) => Ecto.UUID.t() | nil,
          optional(:keychain_credential_id) => Ecto.UUID.t() | nil
        }
  @type violation :: %{
          key: term(),
          field: :project_credential_id | :keychain_credential_id
        }

  @typedoc """
  Human-readable subjects for violation keys (e.g. `~s(job "sync")`), used
  when a violation has no nested changeset to carry its error.
  """
  @type descriptions :: %{optional(term()) => String.t()}

  @doc """
  Every job in a project, shaped as scoping refs for out_of_project_references/2.
  Joins across all the project's workflows (including soft-deleted ones — a
  document that soft-deletes a workflow while planting a cross-project ref on its
  job must still be scanned). `key` is the bare job id; `label` is always selected
  (callers that don't need it ignore it, as out_of_project_references/2 does).
  """
  @spec job_refs_for_project(Ecto.UUID.t()) :: [ref()]
  def job_refs_for_project(project_id) do
    from(j in Job,
      join: w in Workflow,
      on: w.id == j.workflow_id,
      where: w.project_id == ^project_id,
      select: %{
        key: j.id,
        label: j.name,
        project_credential_id: j.project_credential_id,
        keychain_credential_id: j.keychain_credential_id
      }
    )
    |> Repo.all()
  end

  @doc "The jobs of a single workflow, shaped as scoping refs. See job_refs_for_project/1."
  @spec job_refs_for_workflow(Ecto.UUID.t()) :: [ref()]
  def job_refs_for_workflow(workflow_id) do
    from(j in Job,
      where: j.workflow_id == ^workflow_id,
      select: %{
        key: j.id,
        label: j.name,
        project_credential_id: j.project_credential_id,
        keychain_credential_id: j.keychain_credential_id
      }
    )
    |> Repo.all()
  end

  @spec out_of_project_references(Ecto.UUID.t(), [ref()]) :: [violation()]
  def out_of_project_references(project_id, refs) do
    offending_pc =
      offending_ids(ProjectCredential, project_id, refs, :project_credential_id)

    offending_kc =
      offending_ids(
        KeychainCredential,
        project_id,
        refs,
        :keychain_credential_id
      )

    Enum.flat_map(refs, fn ref ->
      violation_for(ref, :project_credential_id, offending_pc) ++
        violation_for(ref, :keychain_credential_id, offending_kc)
    end)
  end

  @doc """
  The human-readable error message for a scoping violation on a given field.

  Shared across every consumer of `out_of_project_references/2` so the wording
  stays consistent wherever a cross-project reference is rejected.
  """
  @spec violation_message(:project_credential_id | :keychain_credential_id) ::
          String.t()
  def violation_message(:project_credential_id),
    do: "credential doesn't exist or isn't available in this project"

  def violation_message(:keychain_credential_id),
    do: "must belong to the same project as the job"

  @doc """
  Attaches each violation whose key matches one of the given nested changesets
  (compared via `key_fun`) as a field error on that changeset. Returns the
  updated changesets together with the violations that matched none of them —
  rows already persisted outside the incoming change.
  """
  @spec attach_violations(
          [Ecto.Changeset.t()],
          [violation()],
          (Ecto.Changeset.t() -> term())
        ) :: {[Ecto.Changeset.t()], [violation()]}
  def attach_violations(changesets, violations, key_fun) do
    Enum.map_reduce(changesets, violations, fn changeset, remaining ->
      {matched, rest} =
        Enum.split_with(remaining, &(&1.key == key_fun.(changeset)))

      changeset =
        Enum.reduce(matched, changeset, fn %{field: field}, cs ->
          Ecto.Changeset.add_error(cs, field, violation_message(field))
        end)

      {changeset, rest}
    end)
  end

  @doc """
  Fails a changeset over scoping violations. Violations that could not be
  attached to a nested changeset (rows persisted outside the incoming change)
  become base errors naming the offending row via `descriptions`, so the
  rejection stays diagnosable even when the change never touched the row.

  `valid?` is forced false regardless: field errors added to nested changesets
  that are re-attached with `put_change/3` do not propagate to the parent.
  """
  @spec invalidate(Ecto.Changeset.t(), [violation()], descriptions()) ::
          Ecto.Changeset.t()
  def invalidate(changeset, unattached_violations, descriptions) do
    unattached_violations
    |> Enum.reduce(changeset, fn %{key: key, field: field}, cs ->
      subject = Map.get(descriptions, key, inspect(key))

      Ecto.Changeset.add_error(
        cs,
        :base,
        "#{subject}: #{violation_message(field)} (#{field})"
      )
    end)
    |> Map.put(:valid?, false)
  end

  defp offending_ids(schema, project_id, refs, field) do
    case ids_for(refs, field) do
      [] ->
        MapSet.new()

      ids ->
        query =
          from(c in schema,
            where:
              c.id in ^ids and
                (is_nil(c.project_id) or c.project_id != ^project_id),
            select: c.id
          )

        query |> Repo.all() |> MapSet.new()
    end
  end

  defp ids_for(refs, field) do
    refs
    |> Enum.map(&Map.get(&1, field))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp violation_for(ref, field, offending) do
    id = Map.get(ref, field)

    if id && MapSet.member?(offending, id) do
      [%{key: ref.key, field: field}]
    else
      []
    end
  end
end
