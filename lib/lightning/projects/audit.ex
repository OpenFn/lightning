defmodule Lightning.Projects.Audit do
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "project",
    events: [
      "dataclip_retention_period_updated",
      "history_retention_period_updated"
    ]

  alias Lightning.Repo

  def audit_history_retention_period_updated(project, changeset, user) do
    event_changeset = filter_changes(changeset, :history_retention_period)

    "history_retention_period_updated"
    |> save_event(project, user, event_changeset)
  end

  def audit_dataclip_retention_period_updated(project, changeset, user) do
    event_changeset = filter_changes(changeset, :dataclip_retention_period)

    "dataclip_retention_period_updated"
    |> save_event(project, user, event_changeset)
  end

  defp filter_changes(%{changes: changes} = changeset, field) do
    changeset |> Map.merge(%{changes: changes |> Map.take([field])})
  end

  defp save_event(event_name, project, user, changeset) do
    event_name
    |> event(project.id, user.id, changeset)
    |> Lightning.Auditing.Audit.save(Repo)
  end
end
