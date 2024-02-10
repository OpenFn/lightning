defmodule LightningWeb.VersionControlController do
  use LightningWeb, :controller

  alias Lightning.VersionControl

  def index(conn, params) do
    # add installation id to project repo
    # {:error, %{reason: "Can't find a pending connection."}}
    user_id = conn.assigns.current_user.id
    pending_connection = VersionControl.get_pending_user_installation(user_id)

    if params["setup_action"] == "update" and is_nil(pending_connection) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(
        200,
        "GitHub installation updated successfully; you may close this page or navigate to any OpenFn project which uses this installation: #{params["installation_id"]}"
      )
    else
      {:ok, project_repo_connection} =
        VersionControl.add_github_installation_id(
          user_id,
          params["installation_id"]
        )

      # get project repo connection and forward to project settings
      redirect(conn,
        to: ~p"/projects/#{project_repo_connection.project_id}/settings#vcs"
      )
    end
  end
end
