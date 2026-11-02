defmodule Lightning.Policies.Account do
  @moduledoc """
  What a person may do to their own account through the API: their personal
  access tokens, their MFA and their GitHub connection.

  Only people have an account, so the service account and repo connections
  are refused every action. Some actions need a person at the keyboard, on the
  session token of Lightning's own app (`Decision.session/3`), and a few of
  those also need the session stepped up: anything that hands out a new way
  into the account, or takes one away. Every rule reads only the caller, so
  `LightningWeb.Plugs.AuthorizeAction` settles each one before a body is read.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Policies.Decision
  alias Lightning.Scope

  @type actions ::
          :list_own_tokens
          | :create_own_token
          | :revoke_own_token
          | :read_own_mfa
          | :start_mfa
          | :enable_mfa
          | :disable_mfa
          | :regenerate_backup_codes
          | :disconnect_github
          | :list_github_repos

  @spec authorize(actions(), Scope.t(), any()) :: Decision.answer()

  # A personal access token may list and revoke its person's tokens, itself
  # included, so a script can rotate its own.
  def authorize(action, %Scope{} = scope, _subject)
      when action in [:list_own_tokens, :revoke_own_token],
      do: Decision.person(scope, true)

  # A new token is a new way into the account that outlives the session. A new
  # authenticator is one too: its codes step a session up, so saving one on a
  # session that hasn't stepped up would hand step-up to anyone at an unlocked
  # browser, and through it every route below.
  def authorize(action, %Scope{} = scope, _subject)
      when action in [:create_own_token, :enable_mfa, :disable_mfa],
      do: Decision.session(scope, true, step_up: true)

  # Backup codes exist only alongside MFA.
  def authorize(:regenerate_backup_codes, %Scope{} = scope, _subject),
    do: Decision.session(scope, mfa_enabled?(scope), step_up: true)

  def authorize(action, %Scope{} = scope, _subject)
      when action in [
             :read_own_mfa,
             :start_mfa,
             :disconnect_github,
             :list_github_repos
           ],
      do: Decision.session(scope, true)

  defp mfa_enabled?(%Scope{actor: %User{mfa_enabled: enabled}}), do: enabled
  defp mfa_enabled?(%Scope{}), do: false
end
