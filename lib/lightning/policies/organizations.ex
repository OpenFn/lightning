defmodule Lightning.Policies.Organizations do
  @moduledoc """
  Who may read, create and manage organizations. Every action needs the
  `organizations:write` grant.

  A superuser and the service account (`Lightning.Scope.instance_wide?/1`)
  may read and manage every organization, and only they may create one. A
  person in an organization may read it and its members, and an admin of it
  may rename it and add, re-role and remove its members.

  An organization is asked about with the caller's role on it loaded
  (`Lightning.Organizations.fetch_organization/2`), so the rule reads only that
  and the scope. Asked with a nil organization, the policy answers for every
  organization: whether the caller may learn which exist, which only an
  instance-wide caller may.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Organizations.Organization
  alias Lightning.Policies.Decision
  alias Lightning.Scope

  @type actions ::
          :read_organization | :create_organization | :manage_organization

  @grant "organizations:write"

  @spec authorize(actions(), Scope.t(), Organization.t() | nil | atom()) ::
          Decision.answer()
  def authorize(:create_organization, %Scope{} = scope, subject),
    do: Decision.instance(scope, subject, @grant, Scope.instance_wide?(scope))

  def authorize(action, %Scope{} = scope, subject)
      when action in [:read_organization, :manage_organization],
      do:
        Decision.instance(
          scope,
          subject,
          @grant,
          allowed?(action, scope, subject)
        )

  defp allowed?(action, scope, subject) do
    Scope.instance_wide?(scope) or role_allows?(action, subject)
  end

  defp role_allows?(:read_organization, %Organization{role: role}),
    do: role in [:admin, :member]

  defp role_allows?(:manage_organization, %Organization{role: role}),
    do: role == :admin

  defp role_allows?(_action, _subject), do: false
end
