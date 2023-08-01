defmodule LightningWeb.VersionControlController do
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias Lightning.VersionControl

  def index(conn, params) do
    token = get_session(conn, :user_token)
    logged_in_user = Accounts.get_user_by_session_token(token)
    # add installation id to project repo 
    {:ok, project_repo} =
      VersionControl.add_github_installation_id(
        logged_in_user.id,
        params["installation_id"]
      )

    # get project repo connection and forward to project settings
    redirect(conn, to: "/projects/" <> project_repo.project_id <> "/settings#vcs")
  end
end
