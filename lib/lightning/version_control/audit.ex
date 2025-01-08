defmodule Lightning.VersionControl.Audit do
  @moduledoc """
  Generate Audit changesets for changes related to VersionControl.
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "project",
    events: [
      "repo_connection_created",
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
      project_id: project_id,
      repo: repo
    } = repo_connection

    changes =
      %{
        branch: branch,
        repo: repo
      }
      |> then(fn connection_properties ->
        if config_path do
          Map.put(connection_properties, :config_path, config_path)
        else
          connection_properties
        end
      end)
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
end
