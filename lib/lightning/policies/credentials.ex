defmodule Lightning.Policies.Credentials do
  @moduledoc """
  The Bodyguard Policy module for authorizing credential actions.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Projects.Project
  alias Lightning.Projects.Scope
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
          user :: User.t(),
          resource :: Project.t()
        ) :: boolean
  def authorize(
        :create_keychain_credential,
        %User{} = user,
        %Project{} = project
      ) do
    admin_or_support?(user, project)
  end

  # KeychainCredential actions - require owner or admin role
  @spec authorize(
          action :: actions(),
          user :: User.t(),
          resource :: KeychainCredential.t()
        ) :: boolean
  def authorize(
        action,
        %User{} = user,
        %KeychainCredential{} = keychain_credential
      )
      when action in [
             :edit_keychain_credential,
             :delete_keychain_credential,
             :view_keychain_credential
           ] do
    admin_or_support?(user, keychain_credential.project_id)
  end

  # Deny by default: a call site passing the wrong shape fails closed rather
  # than raising. Reaching this clause is a bug in the caller — but the debug
  # line is filtered out at prod's :info level, so seeing none of these is not
  # evidence that nobody is hitting it.
  def authorize(action, actor, resource) do
    Logger.debug(fn ->
      "Refused #{inspect(action)} for #{inspect(actor, limit: 2)} " <>
        "on #{inspect(resource, limit: 3)}: no matching policy clause"
    end)

    false
  end

  # Deliberately looser than ProjectUsers, where a support user with no
  # membership row gets nothing at admin level. Keychain access on a consenting
  # project is the pre-existing rule from allow_as_support_user?/2, kept rather
  # than tightened — narrowing it is a support-workflow decision, not a fix.
  defp admin_or_support?(%User{} = user, subject) do
    case Scope.fetch(user, subject) do
      {:ok, %Scope{role: nil, support?: support?}} -> support?
      {:ok, %Scope{role: role}} -> role in [:owner, :admin]
      {:error, _reason} -> false
    end
  end
end
