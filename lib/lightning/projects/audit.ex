defmodule Lightning.Projects.Audit do
  @moduledoc """
  Creates Audit entries for selected changes to project settings.
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "project",
    events: [
      "dataclip_retention_period_updated",
      "history_retention_period_updated"
    ]

  alias Lightning.Repo

  require Logger

  def audit_history_retention_period_updated(project, changeset, user) do
    event_changeset = filter_changes(changeset, :history_retention_period)

    "history_retention_period_updated"
    |> save_event(project, user, event_changeset)
    |> tap(fn
      {:error, changeset} ->
        {before_value, after_value} =
          extract_before_after(changeset, :history_retention_period)

        %{
          project_id: project.id,
          user_id: user.id,
          event: "history_retention_period_updated",
          before_value: before_value,
          after_value: after_value
        }
        |> report_error()

      _ok_response ->
        nil
    end)
  end

  def audit_dataclip_retention_period_updated(project, changeset, user) do
    event_changeset = filter_changes(changeset, :dataclip_retention_period)

    "dataclip_retention_period_updated"
    |> save_event(project, user, event_changeset)
    |> tap(fn
      {:error, changeset} ->
        {before_value, after_value} =
          extract_before_after(changeset, :dataclip_retention_period)

        %{
          project_id: project.id,
          user_id: user.id,
          event: "dataclip_retention_period_updated",
          before_value: before_value,
          after_value: after_value
        }
        |> report_error()

      _ok_response ->
        nil
    end)
  end

  defp filter_changes(%{changes: changes} = changeset, field) do
    changeset |> Map.merge(%{changes: changes |> Map.take([field])})
  end

  defp save_event(event_name, project, user, changeset) do
    event_name
    |> event(project.id, user.id, changeset)
    |> Lightning.Auditing.Audit.save(Repo)
  end

  defp report_error(error_data) do
    Logger.error(%{error: "Saving audit event"} |> Map.merge(error_data))

    Sentry.capture_message(
      "Error saving audit event",
      extra: error_data
    )
  end

  defp extract_before_after(%{data: data, changes: changes}, field) do
    before_value = data |> Map.get(field)
    after_value = changes |> Map.get(field)

    {before_value, after_value}
  end
end
