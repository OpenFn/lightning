defmodule LightningWeb.API.CredentialSchemasTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import Lightning.ServiceAccountHelpers
  import Lightning.AdaptorTestHelpers

  setup :isolated_adaptors

  setup %{conn: conn} do
    seed_credential_schema("dhis2")
    seed_credential_schema("http")
    seed_credential_schema("googlesheets")
    insert(:adaptor, name: "@openfn/language-common", schema_data: nil)
    prime_packages_cache()

    %{conn: session_conn(conn, insert(:user))}
  end

  defp dhis2_schema do
    "test/fixtures/schemas/dhis2.json"
    |> File.read!()
    |> Jason.decode!()
  end

  describe "listing" do
    test "lists raw and every adaptor with a schema, leaving out those that connect through OAuth",
         %{conn: conn} do
      conn = get(conn, ~p"/api/credential_schemas")

      assert json_response(conn, 200) == %{
               "data" => [
                 %{"name" => "raw", "title" => "Raw JSON"},
                 %{"name" => "@openfn/language-dhis2", "title" => "dhis2"},
                 %{"name" => "@openfn/language-http", "title" => "http"}
               ]
             }
    end

    test "a service account with credentials:write lists them" do
      {conn, _account} =
        with_service_account(build_conn(), ["credentials:write"])

      conn = conn |> put_req_header("accept", "application/json")

      assert [%{"name" => "raw"} | _] =
               json_response(get(conn, ~p"/api/credential_schemas"), 200)[
                 "data"
               ]
    end
  end

  describe "reading" do
    test "reads an adaptor's JSON Schema by its package name, its short name, or with an unencoded @",
         %{conn: conn} do
      expected = %{
        "data" => %{
          "name" => "@openfn/language-dhis2",
          "title" => "dhis2",
          "schema" => dhis2_schema()
        }
      }

      for path <- [
            "/api/credential_schemas/%40openfn%2Flanguage-dhis2",
            "/api/credential_schemas/@openfn%2Flanguage-dhis2",
            "/api/credential_schemas/dhis2"
          ] do
        assert json_response(get(conn, path), 200) == expected, path
      end
    end

    test "keeps the schema's keys in the order the adaptor wrote them", %{
      conn: conn
    } do
      conn = get(conn, "/api/credential_schemas/dhis2")

      written =
        "test/fixtures/schemas/dhis2.json"
        |> File.read!()
        |> Jason.decode!(objects: :ordered_objects)

      assert conn.resp_body =~
               Jason.encode!(written["properties"])
    end

    test "raw takes any object, so it has no schema", %{conn: conn} do
      conn = get(conn, ~p"/api/credential_schemas/raw")

      assert json_response(conn, 200) == %{
               "data" => %{
                 "name" => "raw",
                 "title" => "Raw JSON",
                 "schema" => nil
               }
             }
    end

    test "answers 404 not_found for a name the catalogue doesn't hold, and for oauth",
         %{conn: conn} do
      for name <- ["nonesuch", "@openfn/language-nonesuch", "oauth"] do
        conn
        |> get(~p"/api/credential_schemas/#{name}")
        |> assert_problem(404, :not_found, [])
      end
    end
  end

  describe "while the adaptor catalogue can't answer" do
    test "both routes answer 503 not_ready with Retry-After", %{conn: conn} do
      Mimic.stub(Lightning.Adaptors, :packages, fn -> {:error, :not_ready} end)

      Mimic.stub(Lightning.Adaptors, :resolve_name, fn _name ->
        {:error, :timeout}
      end)

      for path <- [
            ~p"/api/credential_schemas",
            ~p"/api/credential_schemas/dhis2"
          ] do
        conn = get(conn, path)
        assert_problem(conn, 503, :not_ready, [])
        assert get_resp_header(conn, "retry-after") == ["5"]
      end
    end
  end
end
