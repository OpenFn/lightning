defmodule CredentialsServiceWeb.CredentialControllerTest do
  use CredentialsServiceWeb.ConnCase, async: false

  alias CredentialsService.Credentials

  defp authed(conn, user_id),
    do: put_req_header(conn, "authorization", "Bearer " <> user_id)

  defp create_for(user_id, name) do
    {:ok, cred} =
      Credentials.create_credential(%{
        "name" => name,
        "user_id" => user_id,
        "body" => %{"password" => "supersecret-marker"}
      })

    cred
  end

  test "rejects requests without a bearer token", %{conn: conn} do
    conn = get(conn, "/api/v1/credentials")
    assert json_response(conn, 401)
  end

  test "POST creates a credential and never returns the body", %{conn: conn} do
    uid = Ecto.UUID.generate()

    conn =
      conn
      |> authed(uid)
      |> post("/api/v1/credentials", %{
        "name" => "My API Key",
        "schema" => "http",
        "bodies" => %{"main" => %{"username" => "u", "password" => "supersecret-marker"}}
      })

    body = json_response(conn, 201)
    assert body["data"]["type"] == "credentials"
    assert body["data"]["attributes"]["name"] == "My API Key"
    assert body["data"]["attributes"]["environments"] == ["main"]

    # the secret must not appear anywhere in the response
    refute inspect(body) =~ "supersecret-marker"
    refute Map.has_key?(body["data"]["attributes"], "body")
  end

  test "GET index lists the caller's credentials", %{conn: conn} do
    uid = Ecto.UUID.generate()
    _ = create_for(uid, "Listed")

    conn = conn |> authed(uid) |> get("/api/v1/credentials")
    body = json_response(conn, 200)

    names = Enum.map(body["data"], & &1["attributes"]["name"])
    assert "Listed" in names
  end

  test "GET show returns 200, and 404 for unknown", %{conn: conn} do
    uid = Ecto.UUID.generate()
    cred = create_for(uid, "Shown")

    ok = conn |> authed(uid) |> get("/api/v1/credentials/#{cred.id}")
    assert json_response(ok, 200)["data"]["id"] == cred.id

    missing = conn |> authed(uid) |> get("/api/v1/credentials/#{Ecto.UUID.generate()}")
    assert json_response(missing, 404)
  end

  test "DELETE succeeds for the owner and is forbidden for others", %{conn: conn} do
    owner = Ecto.UUID.generate()
    other = Ecto.UUID.generate()
    cred = create_for(owner, "Owned")

    forbidden = conn |> authed(other) |> delete("/api/v1/credentials/#{cred.id}")
    assert json_response(forbidden, 403)

    ok = conn |> authed(owner) |> delete("/api/v1/credentials/#{cred.id}")
    assert response(ok, 204)
    assert Credentials.get_credential(cred.id) == nil
  end
end
