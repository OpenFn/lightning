defmodule Lightning.Projects.Audit do
  @moduledoc """
  Generate Audit changesets for selected changes to project settings.
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "project",
    events: [
      "allow_support_access_updated",
      "collaborator_added",
      "collaborator_removed",
      "collaborator_role_changed",
      "created",
      "dataclip_retention_period_updated",
      "description_updated",
      "history_retention_period_updated",
      "name_updated",
      "requires_mfa_updated"
    ]

  alias Ecto.Multi
  alias Lightning.Projects.Project

  def derive_events(multi, changeset, user) do
    [
      :allow_support_access,
      :dataclip_retention_period,
      :description,
      :history_retention_period,
      :name,
      :requires_mfa
    ]
    |> Enum.reduce(multi, fn field, multi ->
      changeset
      |> filter_change(field)
      |> event_changeset(field, user)
      |> case do
        :no_changes ->
          multi

        audit_changeset ->
          Multi.insert(multi, operation(field), audit_changeset)
      end
    end)
  end

  @doc """
  Appends the events for a newly created project: `created`, then one
  `collaborator_added` per member in its `project_users`.
  """
  def derive_creation_events(multi, %Project{} = project, actor) do
    multi
    |> Multi.insert(
      :audit_created,
      event("created", project.id, actor, %{
        before: nil,
        after: %{"name" => project.name, "description" => project.description}
      })
    )
    |> derive_membership_events(
      project.id,
      Enum.map(project.project_users, &{:added, &1}),
      actor
    )
  end

  @doc """
  Appends an audit event for every collaborator change in `changes`.

  Step keys carry the affected user's id, which is unique within a single
  membership write.
  """
  def derive_membership_events(multi, project_id, changes, actor) do
    Enum.reduce(changes, multi, fn change, multi ->
      Multi.insert(
        multi,
        audit_key(change),
        membership_event(project_id, change, actor)
      )
    end)
  end

  defp audit_key({:added, %{user_id: user_id}}),
    do: {:audit_collaborator_added, user_id}

  defp audit_key({:role_changed, %{user_id: user_id}}),
    do: {:audit_collaborator_role_changed, user_id}

  defp audit_key({:removed, %{user_id: user_id}}),
    do: {:audit_collaborator_removed, user_id}

  defp membership_event(project_id, {:added, member}, actor) do
    event("collaborator_added", project_id, actor, %{
      before: nil,
      after: membership_fields(member.user_id, member.role)
    })
  end

  defp membership_event(project_id, {:role_changed, member}, actor) do
    event("collaborator_role_changed", project_id, actor, %{
      before: membership_fields(member.user_id, member.previous_role),
      after: membership_fields(member.user_id, member.role)
    })
  end

  defp membership_event(project_id, {:removed, member}, actor) do
    event("collaborator_removed", project_id, actor, %{
      before: membership_fields(member.user_id, member.role),
      after: nil
    })
  end

  defp membership_fields(user_id, role) do
    %{"user_id" => user_id, "role" => to_string(role)}
  end

  defp operation(field), do: "audit_#{field}"

  defp event_changeset(%Ecto.Changeset{} = changeset, field, user) do
    project_id = Ecto.Changeset.get_field(changeset, :id)

    event("#{field}_updated", project_id, user, changeset)
  end

  # Strips out all changes except for the specified field
  # We do this to ensure that we only audit the changes we care about
  defp filter_change(changeset, field) do
    Map.put(
      changeset,
      :changes,
      changeset.changes |> Map.filter(fn {f, _} -> f == field end)
    )
  end
end
