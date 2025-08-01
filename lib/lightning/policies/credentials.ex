defmodule Lightning.Policies.Credentials do
  @moduledoc """
  The Bodyguard Policy module for authorizing credential actions.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectUser
  require Logger

  @type actions ::
          :create_keychain_credential
          | :edit_keychain_credential
          | :delete_keychain_credential
          | :view_keychain_credential

  @doc """
  Authorize credential actions based on the user's project role.

  For KeychainCredential resources, users must have owner or admin role
  in the associated project.
  """
  def authorize(action, user, resource)

  @spec authorize(
          action :: actions(),
          project_user :: ProjectUser.t(),
          resource :: any()
        ) :: boolean
  def authorize(
        :create_keychain_credential,
        %User{} = user,
        %{project: project, project_user: project_user}
      ) do
    (!!project_user and project_user.role in [:owner, :admin]) or
      ProjectUsers.allow_as_support_user?(user, project)
  end

  # User with project - check project membership or support user access
  def authorize(
        :create_keychain_credential,
        %User{} = user,
        %Project{} = project
      ) do
    case Projects.get_project_user(project, user) do
      %ProjectUser{} = project_user ->
        Bodyguard.permit?(
          __MODULE__,
          :create_keychain_credential,
          user,
          %{project_user: project_user, project: project}
        )

      nil ->
        # No project membership - check if support user with project access
        ProjectUsers.allow_as_support_user?(user, project)
    end
  end

  # KeychainCredential actions - require owner or admin role
  @spec authorize(
          action :: actions(),
          user_or_project_user :: User.t() | ProjectUser.t(),
          resource :: KeychainCredential.t()
        ) :: boolean
  def authorize(
        action,
        user_or_project_user,
        %KeychainCredential{} = keychain_credential
      )
      when action in [
             :edit_keychain_credential,
             :delete_keychain_credential,
             :view_keychain_credential
           ] do
    # Check if user is a support user first
    case user_or_project_user do
      %User{support_user: true} ->
        true

      _ ->
        get_project_user(keychain_credential, user_or_project_user)
        |> case do
          %ProjectUser{} = project_user ->
            project_user.role in [:owner, :admin]

          _ ->
            false
        end
    end
  end

  # Commented out for now, to make it easier to see which callers are not
  # using the correct arguments
  # Fallback to deny access
  # def authorize(action, user, params) do
  #   Logger.debug(
  #     "Unauthorized action: #{action} for user: #{user.id} with params: #{inspect(params, limit: 3)}"
  #   )
  #
  #   false
  # end

  defp get_project_user(keychain_credential, user_or_project_user) do
    case user_or_project_user do
      %User{} = user ->
        Projects.get_project_user(keychain_credential.project_id, user)

      %ProjectUser{} = project_user ->
        project_user
    end
  end
end
