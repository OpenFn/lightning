defmodule Lightning.Projects.Audit do
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "project",
    events: [
      "dataclip_retention_period_updated",
      "history_retention_period_updated"
    ]

  alias Ecto.Changeset
  alias Lightning.Repo

  def audit_history_retention_period_updated(project, changeset, user) do
    if Changeset.changed?(changeset, :history_retention_period) do
      history_retention_period =
        Changeset.get_change(changeset, :history_retention_period)

      event_changeset =
        changeset
        |> Map.merge(
          %{changes: %{history_retention_period: history_retention_period}}
        )

      "history_retention_period_updated"
      |> event(project.id, user.id, event_changeset)
      |> Lightning.Auditing.Audit.save(Repo)
    end
  end

  def audit_dataclip_retention_period_updated(project, changeset, user) do
    if Changeset.changed?(changeset, :dataclip_retention_period) do
      dataclip_retention_period =
        Changeset.get_change(changeset, :dataclip_retention_period)

      event_changeset =
        changeset
        |> Map.merge(
          %{changes: %{dataclip_retention_period: dataclip_retention_period}}
        )

      "dataclip_retention_period_updated"
      |> event(project.id, user.id, event_changeset)
      |> Lightning.Auditing.Audit.save(Repo)
    end
  end
end
