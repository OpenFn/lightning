defmodule Lightning.Policies.RepoConnections do
  @moduledoc """
  Who may read, write and sync a project's GitHub repo connection through the
  API.

  Each action is a `Lightning.Policies.ProjectUsers` action, so the roles are
  the ones the project settings page uses: any member reads the connection,
  owners and admins connect and disconnect it (`:write_github_connection`), and
  editors and above start a sync (`:initiate_github_sync`). Only a person may
  act, on a personal access or session token. Connecting and disconnecting
  write to the repo with the caller's own GitHub account, and the service
  account has none.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Policies.Decision
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Scope

  @type actions ::
          :see_repo_connection | :write_repo_connection | :sync_repo_connection

  @spec authorize(actions(), Scope.t(), term()) :: Decision.answer()
  def authorize(action, %Scope{} = scope, subject),
    do:
      Decision.person(
        scope,
        ProjectUsers.authorize(project_users_action(action), scope, subject)
      )

  def authorize(_action, _actor, _subject), do: false

  defp project_users_action(:see_repo_connection), do: :access_project
  defp project_users_action(:write_repo_connection), do: :write_github_connection
  defp project_users_action(:sync_repo_connection), do: :initiate_github_sync
end
