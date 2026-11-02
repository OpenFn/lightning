defmodule LightningWeb.API.RepoConnectionJSON do
  @moduledoc false

  import LightningWeb.API.Helpers

  alias Lightning.VersionControl.ProjectRepoConnection
  alias LightningWeb.Router.Helpers, as: Routes

  # `problems` is nil after a write, which has just put every part in the repo
  # rather than read it back.
  def render("show.json", %{
        repo_connection: repo_connection,
        problems: problems,
        conn: conn
      }) do
    self =
      Routes.api_repo_connection_url(conn, :show, repo_connection.project_id)

    %{
      data: %{
        type: "repo_connections",
        id: repo_connection.id,
        attributes:
          repo_connection
          |> Map.take([
            :repo,
            :branch,
            :github_installation_id,
            :inserted_at,
            :updated_at
          ])
          |> Map.merge(%{
            config_path: ProjectRepoConnection.config_path(repo_connection),
            verified: problems in [nil, []],
            problems: problems || []
          }),
        relationships: %{},
        links: %{self: self}
      },
      links: %{self: self_url(conn)}
    }
  end
end
