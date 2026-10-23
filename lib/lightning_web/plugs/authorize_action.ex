defmodule LightningWeb.Plugs.AuthorizeAction do
  @moduledoc """
  Refuses an API action early, on facts about the caller alone, before the
  action parses a body or loads anything.

      plug AuthorizeAction, {:project_users, :access_project} when action == :show

  It asks `Lightning.Policies.Permissions.permit/3` before any project is
  loaded. A refusal is answered by `LightningWeb.API.FallbackController`. A pass
  assigns the caller's scope as `:scope` for the action to reuse, and the action
  still asks `permit/4` about its target. An action with no target asks
  nothing more.
  """
  alias Lightning.Policies.Permissions
  alias Lightning.Scope
  alias LightningWeb.API.FallbackController

  def init({_policy, _action} = permission), do: permission

  def call(conn, {policy, action}) do
    scope = Scope.new(conn.assigns.current_resource)

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
