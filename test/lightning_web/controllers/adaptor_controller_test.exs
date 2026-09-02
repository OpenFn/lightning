defmodule LightningWeb.AdaptorControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  alias Lightning.AdaptorTestHelpers
  alias Lightning.Adaptors.Catalogue
  alias LightningWeb.AdaptorIconURL

  describe "GET /adaptors/catalogue" do
    # The production cache outlives the SQL sandbox, so an entry another
    # test committed would otherwise be served here.
    setup %{conn: conn} do
      AdaptorTestHelpers.clear_global_adaptors_cache()

      %{conn: log_in_user(conn, insert(:user))}
    end

    test "returns every adaptor with name, latest_version, versions, icon_urls, and repository",
         %{conn: conn} do
      square_sha = :crypto.hash(:sha256, "square")

      {:ok, _adaptor} =
        Catalogue.upsert_adaptor(%{
          name: "@openfn/language-http",
          source: :npm,
          latest_version: "2.0.0",
          repository: "https://github.com/openfn/language-http",
          icon_square_ext: "png",
          icon_square_sha256: square_sha,
          icon_rectangle_ext: nil,
          icon_rectangle_sha256: nil,
          versions: [version_record("1.0.0"), version_record("2.0.0")]
        })

      conn = get(conn, ~p"/adaptors/catalogue")

      assert %{"data" => [entry]} = json_response(conn, 200)

      expected_square_url =
        AdaptorIconURL.build(
          "@openfn/language-http",
          %{icon_square_ext: "png", icon_square_sha256: square_sha},
          :square
        )

      assert entry["name"] == "@openfn/language-http"
      assert entry["latest_version"] == "2.0.0"
      assert entry["repository"] == "https://github.com/openfn/language-http"
      assert Enum.sort(entry["versions"]) == ["1.0.0", "2.0.0"]
      assert entry["icon_urls"]["square"] == expected_square_url
      assert entry["icon_urls"]["rectangle"] == nil
    end

    test "a repeat request with a matching If-None-Match returns 304 with no body",
         %{
           conn: conn
         } do
      {:ok, _adaptor} =
        Catalogue.upsert_adaptor(%{
          name: "@openfn/language-http",
          source: :npm,
          latest_version: "1.0.0",
          versions: [version_record("1.0.0")]
        })

      first = get(conn, ~p"/adaptors/catalogue")
      [etag] = get_resp_header(first, "etag")

      second =
        conn
        |> put_req_header("if-none-match", etag)
        |> get(~p"/adaptors/catalogue")

      assert response(second, 304) == ""
    end

    test "removing a version from an adaptor that doesn't hold the current max changes the ETag",
         %{
           conn: conn
         } do
      {:ok, _b} =
        Catalogue.upsert_adaptor(%{
          name: "@openfn/language-b",
          source: :npm,
          latest_version: "1.0.0",
          versions: [version_record("1.0.0")]
        })

      {:ok, _a} =
        Catalogue.upsert_adaptor(%{
          name: "@openfn/language-a",
          source: :npm,
          latest_version: "1.0.0",
          versions: [version_record("1.0.0")]
        })

      first = get(conn, ~p"/adaptors/catalogue")
      [first_etag] = get_resp_header(first, "etag")

      {:ok, _b} =
        Catalogue.upsert_adaptor(%{
          name: "@openfn/language-b",
          source: :npm,
          latest_version: "1.0.0",
          versions: []
        })

      # A bare `upsert_adaptor/1` broadcasts nothing, so nothing evicts the
      # cached stamp; the Scheduler and Seed are what announce a change.
      AdaptorTestHelpers.clear_global_adaptors_cache()

      second = get(conn, ~p"/adaptors/catalogue")
      [second_etag] = get_resp_header(second, "etag")

      assert first_etag != second_etag

      third =
        conn
        |> put_req_header("if-none-match", first_etag)
        |> get(~p"/adaptors/catalogue")

      assert response(third, 200)
    end
  end

  test "an unauthenticated request is rejected with a JSON 401", %{conn: conn} do
    conn = get(conn, ~p"/adaptors/catalogue")

    assert json_response(conn, 401) == %{"error" => "Unauthorized"}
  end

  defp version_record(version) do
    %{
      version: version,
      integrity: "sha512-#{version}",
      tarball_url: "https://example.com/x/-/x-#{version}.tgz",
      size_bytes: 1024,
      dependencies: %{},
      peer_dependencies: %{},
      published_at: nil,
      deprecated: false
    }
  end
end
