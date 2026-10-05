defmodule Lightning.Policies.Exports do
  @moduledoc """
  The Bodyguard Policy module for Exports.

  Downloading an export archive is exactly project access, so this delegates
  rather than re-deciding. The previous implementation built a `%Project{}` from
  the file's `project_id` and asked whether the user was a member of it, which
  could not see `scheduled_deletion` and so served archives from projects that
  had been shut down.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Policies.Permissions
  alias Lightning.Projects.File, as: ProjectFile

  @type actions :: :download

  @spec authorize(actions(), User.t(), ProjectFile.t()) ::
          boolean() | {:error, :forbidden}
  def authorize(:download, %User{} = user, %ProjectFile{} = project_file) do
    Permissions.can?(:project_users, :access_project, user, project_file) or
      {:error, :forbidden}
  end
end
