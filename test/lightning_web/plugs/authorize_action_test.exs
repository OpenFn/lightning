defmodule LightningWeb.Plugs.AuthorizeActionTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  alias Lightning.Scope
  alias LightningWeb.Plugs.AuthorizeAction

  defp run(conn, actor) do
    conn
    |> Phoenix.Controller.put_format("json")
    |> assign(:current_resource, actor)
    |> AuthorizeAction.call(
      AuthorizeAction.init({:project_users, :access_project})
    )
  end

  test "assigns the caller's project-less scope when nothing refuses", %{
    conn: conn
  } do
    user = insert(:user)
    conn = run(conn, user)

    refute conn.halted
    assert conn.assigns.scope == Scope.new(user)
  end

  test "halts with the fallback's answer for a missing grant", %{conn: conn} do
    {account, _private_key} =
      Lightning.ServiceAccountHelpers.service_account_with_key()

    conn = run(conn, %{account | grants: MapSet.new(["users:read"])})

    assert conn.halted
    assert json_response(conn, 403) == %{"error" => "insufficient_scope"}
    refute Map.has_key?(conn.assigns, :scope)
  end
end
