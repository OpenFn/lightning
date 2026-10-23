defmodule Lightning.VersionControl.Audit do
  @moduledoc """
  Generate Audit changesets for changes related to VersionControl.
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "project",
    events: [
      "repo_connection_created",
      "repo_connection_updated",
      "repo_connection_removed"
    ]

  @spec repo_connection(
          Lightning.VersionControl.ProjectRepoConnection.t(),
          :created | :removed,
          Lightning.Accounts.User.t()
          | Lightning.VersionControl.ProjectRepoConnection.t()
          | Lightning.Workflows.Trigger.t()
        ) :: Ecto.Changeset.t()
  def repo_connection(repo_connection, action, actor) do
    %{
      branch: branch,
      config_path: config_path,
      workspace_path: workspace_path,
      project_id: project_id,
      repo: repo
    } = repo_connection

    changes =
      %{
        branch: branch,
        repo: repo
      }
      |> Map.merge(
        Map.reject(
          %{config_path: config_path, workspace_path: workspace_path},
          fn {_key, value} -> is_nil(value) end
        )
      )
      |> then(fn connection_properties ->
        if action == :created do
          %{
            after:
              Map.put(
                connection_properties,
                :sync_direction,
                repo_connection.sync_direction
              )
          }
        else
          %{before: connection_properties}
        end
      end)

    event("repo_connection_#{action}", project_id, actor, changes)
  end

  @doc "A reconnect that moved the connection to another workspace folder"
  def repo_connection_updated(before, updated, actor) do
    event("repo_connection_updated", before.project_id, actor, %{
      before: %{workspace_path: before.workspace_path},
      after: %{workspace_path: updated.workspace_path}
    })
  end
end
