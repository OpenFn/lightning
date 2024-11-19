defmodule Lightning.Projects.Audit do
  @moduledoc """
  Generate Audit changesets for selected changes to project settings.
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "project",
    events: [
      "dataclip_retention_period_updated",
      "history_retention_period_updated",
      "repo_connection_created"
    ]

  alias Ecto.Multi

  def derive_events(multi, changeset, user) do
    [:history_retention_period, :dataclip_retention_period]
    |> Enum.reduce(multi, fn field, multi ->
      changeset
      |> filter_change(field)
      |> event_changeset(field, user)
      |> case do
        :no_changes ->
          multi

        audit_changeset ->
          Multi.insert(multi, operation_name(field), audit_changeset)
      end
    end)
  end

  defp event_changeset(%Ecto.Changeset{} = changeset, field, user) do
    project_id = Ecto.Changeset.get_field(changeset, :id)

    event("#{field}_updated", project_id, user, changeset)
  end

  defp operation_name(:dataclip_retention_period), do: :audit_dataclip_retention
  defp operation_name(:history_retention_period), do: :audit_history_retention

  # Strips out all changes except for the specified field
  # We do this to ensure that we only audit the changes we care about
  defp filter_change(changeset, field) do
    Map.put(
      changeset,
      :changes,
      changeset.changes |> Map.filter(fn {f, _} -> f == field end)
    )
  end

  def repo_connection_created(repo_connection, user) do
    %{
      branch: branch,
      config_path: config_path,
      project_id: project_id,
      repo: repo,
      sync_direction: sync_direction
    } = repo_connection

    connection_properties =
      %{
        branch: branch,
        repo: repo,
        sync_direction: sync_direction
      }
      |> Map.merge(
        case config_path do
          nil -> %{}
          path -> %{config_path: path}
        end
      )

    changes = %{after: connection_properties}

    event("repo_connection_created", project_id, user, changes)
  end
end
