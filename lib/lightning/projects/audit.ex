defmodule Lightning.Projects.Audit do
  @moduledoc """
  Generate Audit changesets for selected changes to project settings.
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "project",
    events: [
      "allow_support_access_updated",
      "dataclip_retention_period_updated",
      "history_retention_period_updated",
      "requires_mfa_updated"
    ]

  alias Ecto.Multi

  def derive_events(multi, changeset, user) do
    [
      :allow_support_access,
      :dataclip_retention_period,
      :history_retention_period,
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
          Multi.insert(multi, field, audit_changeset)
      end
    end)
  end

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
