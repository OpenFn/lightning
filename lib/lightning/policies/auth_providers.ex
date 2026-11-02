defmodule Lightning.Policies.AuthProviders do
  @moduledoc """
  Who may read and change the instance's single sign-on provider: a superuser,
  on a personal access token or a session token. It is instance configuration,
  not a project's, and no token grant covers it, so the service account and
  repo connections are refused. The rule reads only the caller, so
  `LightningWeb.Plugs.AuthorizeAction` settles it before anything is loaded.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Policies.Decision
  alias Lightning.Scope

  @type actions :: :read_auth_provider | :write_auth_provider

  @spec authorize(actions(), Scope.t(), any()) :: Decision.answer()
  def authorize(action, %Scope{} = scope, _subject)
      when action in [:read_auth_provider, :write_auth_provider],
      do: Decision.person(scope, scope.instance_role == :superuser)
end
