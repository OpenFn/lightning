defmodule LightningWeb.API.RegistrationControllerTest do
  use LightningWeb.ConnCase, async: true

  import Mox

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  test "create", %{conn: conn} do
    conn = post(conn, ~p"/api/users/register")

    assert %{"error" => "Not Implemented"} == json_response(conn, 501)
  end

  test "create with valid extension", %{conn: conn} do
    defmodule LightningWeb.API.TestRegistrationController do
      use Phoenix.Controller,
        formats: [:html, :json]

      def create(conn, _params) do
        conn |> put_status(200) |> json(%{message: "Hello, World!"})
      end
    end

    stub(Lightning.MockConfig, :get_extension_mod, fn _ ->
      LightningWeb.API.TestRegistrationController
    end)

    conn = post(conn, ~p"/api/users/register")

    assert json_response(conn, 200) == %{"message" => "Hello, World!"}
  end
end
