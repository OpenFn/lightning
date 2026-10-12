defmodule LightningWeb.Plugs.AuthorizeAction do
  @moduledoc """
  Refuses an API action early, on what the caller alone decides, before the
  action parses a body or loads anything.

      plug AuthorizeAction, {:project_users, :access_project} when action == :show

  It asks `Lightning.Policies.Permissions.permit/3` about the caller's
  project-less scope. A refusal goes to `LightningWeb.FallbackController`; a
  pass assigns that scope as `:scope` for the action to reuse. A pass is not
  permission: every action behind this plug still asks `permit/4` about its
  target.
  """
  alias Lightning.Policies.Permissions
  alias Lightning.Scope

  def init({policy, action}), do: {policy, action}

  def call(conn, {policy, action}) do
    scope = Scope.new(conn.assigns.current_resource)

    case Permissions.permit(policy, action, scope) do
      :ok ->
        Plug.Conn.assign(conn, :scope, scope)

      error ->
        conn
        |> LightningWeb.FallbackController.call(error)
        |> Plug.Conn.halt()
    end
  end
end
