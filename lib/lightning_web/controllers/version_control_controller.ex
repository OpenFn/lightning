defmodule LightningWeb.VersionControlController do
  use LightningWeb, :controller

  alias Lightning.VersionControl

  def index(conn, params) do
    # add installation id to project repo
    # {:error, %{reason: "Can't find a pending connection."}}

    {:ok, project_repo_connection} =
      VersionControl.add_github_installation_id(
        conn.assigns.current_user.id,
        params["installation_id"]
      )

    # get project repo connection and forward to project settings
    redirect(conn,
      to: ~p"/projects/#{project_repo_connection.project_id}/settings#vcs"
    )
  end
end
