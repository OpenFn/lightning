defmodule LightningWeb.Plugs.AuthorizeAction do
  @moduledoc """
  Refuses an API action early, on facts about the caller alone, before the
  action parses a body or loads anything.

      plug AuthorizeAction, {:project_users, :access_project} when action == :show

  It runs after the pipeline has authenticated the caller. It builds the
  caller's `Lightning.Scope`, with the token kind the pipeline assigned, and
  asks `Lightning.Policies.Permissions.permit/3`, which checks only facts about
  the caller: the token grant, and for a rule built on
  `Lightning.Policies.Decision.session/3` or `person/2`, the token kind and
  step-up. A refusal is answered by
  `LightningWeb.API.FallbackController`. A pass assigns the scope as `:scope`
  for the action to reuse. Passing is not permission: an action with a target
  still asks about it through `LightningWeb.API.Target`.
  """
  alias Lightning.Policies.Permissions
  alias Lightning.Scope
  alias LightningWeb.API.FallbackController

  def init({_policy, _action} = permission), do: permission

  def call(conn, {policy, action}) do
    scope =
      Scope.new(conn.assigns.current_resource,
        token_kind: conn.assigns[:token_kind],
        stepped_up_until: conn.assigns[:stepped_up_until]
      )

    case Permissions.permit(policy, action, scope) do
      :ok ->
        Plug.Conn.assign(conn, :scope, scope)

      error ->
        conn
        |> FallbackController.call(error)
        |> Plug.Conn.halt()
    end
  end
end
