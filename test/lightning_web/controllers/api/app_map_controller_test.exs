defmodule LightningWeb.API.AppMapControllerTest do
  use LightningWeb.ConnCase, async: true

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index without authentication" do
    test "is rejected with a 401", %{conn: conn} do
      conn = get(conn, ~p"/api/app_map")

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "index as a regular user" do
    setup [:register_and_log_in_user]

    test "returns the app map pages", %{conn: conn} do
      conn = get(conn, ~p"/api/app_map")

      assert %{"pages" => [_ | _] = pages} = json_response(conn, 200)

      for page <- pages do
        assert %{"id" => id, "path" => path, "description" => description} =
                 page

        assert is_binary(id) and id != ""
        assert is_binary(path) and path != ""
        assert is_binary(description) and description != ""
      end
    end

    test "omits admin-section pages", %{conn: conn} do
      conn = get(conn, ~p"/api/app_map")

      assert %{"pages" => [_ | _] = pages} = json_response(conn, 200)

      refute Enum.any?(pages, &(&1["section"] == "admin"))
      assert Enum.any?(pages, &(&1["section"] == "project"))
      assert Enum.any?(pages, &(&1["section"] == "user"))
    end
  end

  describe "index as a superuser" do
    setup [:register_and_log_in_superuser]

    test "includes admin-section pages", %{conn: conn} do
      conn = get(conn, ~p"/api/app_map")

      assert %{"pages" => [_ | _] = pages} = json_response(conn, 200)

      assert Enum.any?(pages, &(&1["section"] == "admin"))
      assert Enum.any?(pages, &(&1["section"] == "project"))
      assert Enum.any?(pages, &(&1["section"] == "user"))
    end
  end
end
