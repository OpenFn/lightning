defmodule Lightning.Projects.Audit do
  @moduledoc """
  Generate Audit changesets for selected changes to project settings.
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "project",
    events: [
      "dataclip_retention_period_updated",
      "history_retention_period_updated"
    ]

  alias Ecto.Multi

  require Logger

  def history_retention_auditing_operation(
        %{project: %{history_retention_period: new_value}},
        %{data: project} = _original_changeset,
        user
      ) do
    build_multi(:history_retention_period, new_value, project, user)
  end

  def history_retention_auditing_operation(_changes, _project, _user) do
    Multi.new()
  end

  def dataclip_retention_auditing_operation(
        %{project: %{dataclip_retention_period: new_value}},
        %{data: project} = _original_changeset,
        user
      ) do
    build_multi(:dataclip_retention_period, new_value, project, user)
  end

  def dataclip_retention_auditing_operation(_changes, _project, _user) do
    Multi.new()
  end

  defp build_multi(field, new_value, project, user) do
    base_changeset =
      project |> Ecto.Changeset.change(%{field => new_value})

    case event_changeset(field, base_changeset, user) do
      :no_changes ->
        Multi.new()

      changeset ->
        Multi.new() |> Multi.insert(operation_name(field), changeset)
    end
  end

  defp event_changeset(field, %{data: %{id: project_id}} = changeset, user) do
    "#{field}_updated"
    |> event(project_id, user.id, changeset)
  end

  defp operation_name(:dataclip_retention_period), do: :audit_dataclip_retention
  defp operation_name(:history_retention_period), do: :audit_history_retention
end
