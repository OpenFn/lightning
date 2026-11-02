defmodule Lightning.Policies.WebhookAuthMethods do
  @moduledoc """
  The Bodyguard Policy module for a project's webhook auth methods on the API.

  Only people reach them, on a personal access token or a session token. The
  service account and a repo connection are refused with `false` whatever
  their grants, since `Lightning.Policies.Decision.person/2` decides first.

  The rules are the ones the project settings page applies, read from
  `Lightning.Policies.ProjectUsers`:

    * `:list_webhook_auth_methods` is `:access_project`, any member.
    * `:manage_webhook_auth_method` (reading one, with or without its
      secrets, creating, replacing and deleting it) is
      `:write_webhook_auth_method`, an owner or admin.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Policies.Decision
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Scope

  @type actions :: :list_webhook_auth_methods | :manage_webhook_auth_method

  @spec authorize(actions(), Scope.t(), Scope.subject() | :before_target) ::
          Decision.answer()
  def authorize(action, %Scope{} = scope, subject),
    do:
      Decision.person(
        scope,
        ProjectUsers.authorize(rule(action), scope, subject)
      )

  defp rule(:list_webhook_auth_methods), do: :access_project
  defp rule(:manage_webhook_auth_method), do: :write_webhook_auth_method
end
