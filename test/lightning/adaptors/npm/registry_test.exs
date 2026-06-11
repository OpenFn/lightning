defmodule Lightning.Adaptors.NPM.RegistryTest do
  use ExUnit.Case, async: false

  alias Lightning.Adaptors.NPM.Registry

  setup do
    bypass = Bypass.open()

    Application.put_env(:lightning, Lightning.Adaptors.NPM,
      registry_url: "http://localhost:#{bypass.port}",
      http_timeout: 1_000
    )

    # Per-test Tesla adapter override — config/test.exs globally pins
    # `Lightning.Tesla.Mock`, but we need the real Finch adapter so that
    # Bypass actually receives requests over a socket.
    prev_adapter = Application.get_env(:tesla, :adapter)

    Application.put_env(
      :tesla,
      :adapter,
      {Tesla.Adapter.Finch, name: Lightning.Finch}
    )

    on_exit(fn ->
      Application.delete_env(:lightning, Lightning.Adaptors.NPM)

      if prev_adapter do
        Application.put_env(:tesla, :adapter, prev_adapter)
      else
        Application.delete_env(:tesla, :adapter)
      end
    end)

    %{bypass: bypass}
  end

  describe "list_adaptors/0" do
    test "returns an empty list when the search has no results", %{
      bypass: bypass
    } do
      Bypass.expect(bypass, "GET", "/-/v1/search", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["text"] == "@openfn"
        assert conn.query_params["size"] == "250"

        json_resp(conn, 200, %{"objects" => []})
      end)

      assert {:ok, []} = Registry.list_adaptors()
    end

    test "returns name + latest_version for each search hit", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/-/v1/search", fn conn ->
        body = %{
          "objects" => [
            %{
              "package" => %{
                "name" => "@openfn/language-http",
                "version" => "2.1.0"
              }
            },
            %{
              "package" => %{
                "name" => "@openfn/language-salesforce",
                "version" => "4.6.3"
              }
            }
          ]
        }

        json_resp(conn, 200, body)
      end)

      {:ok, listing} = Registry.list_adaptors()

      assert Enum.sort_by(listing, & &1.name) == [
               %{name: "@openfn/language-http", latest_version: "2.1.0"},
               %{name: "@openfn/language-salesforce", latest_version: "4.6.3"}
             ]
    end

    test "filters out @openfn/* packages that aren't language-* adaptors and other scopes",
         %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/-/v1/search", fn conn ->
        body = %{
          "objects" => [
            %{
              "package" => %{
                "name" => "@openfn/language-http",
                "version" => "1.0.0"
              }
            },
            %{
              "package" => %{"name" => "@openfn/cli", "version" => "1.2.3"}
            },
            %{
              "package" => %{
                "name" => "@openfn/buildtools",
                "version" => "0.9.0"
              }
            },
            %{
              "package" => %{
                "name" => "@sid-indonesia/language-http",
                "version" => "2.0.0"
              }
            },
            %{
              "package" => %{
                "name" => "language-template",
                "version" => "3.0.0"
              }
            }
          ]
        }

        json_resp(conn, 200, body)
      end)

      assert {:ok, [%{name: "@openfn/language-http", latest_version: "1.0.0"}]} =
               Registry.list_adaptors()
    end

    test "skips malformed entries that lack name or version", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/-/v1/search", fn conn ->
        body = %{
          "objects" => [
            %{
              "package" => %{
                "name" => "@openfn/language-http",
                "version" => "1.0.0"
              }
            },
            %{"package" => %{"name" => "@openfn/language-no-version"}},
            %{"score" => %{"final" => 0.5}}
          ]
        }

        json_resp(conn, 200, body)
      end)

      assert {:ok, [%{name: "@openfn/language-http", latest_version: "1.0.0"}]} =
               Registry.list_adaptors()
    end

    test "surfaces 5xx responses as {:error, _}", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/-/v1/search", fn conn ->
        Plug.Conn.resp(conn, 503, "")
      end)

      assert {:error, {:http_status, 503}} = Registry.list_adaptors()
    end

    test "surfaces network failure as {:error, _}", %{bypass: bypass} do
      Bypass.down(bypass)
      assert {:error, _reason} = Registry.list_adaptors()
    end
  end

  describe "get_packument/1" do
    test "returns the decoded map on 200", %{bypass: bypass} do
      packument = %{
        "name" => "@openfn/language-http",
        "dist-tags" => %{"latest" => "2.1.0"}
      }

      Bypass.expect(bypass, "GET", "/@openfn/language-http", fn conn ->
        json_resp(conn, 200, packument)
      end)

      assert {:ok, ^packument} = Registry.get_packument("@openfn/language-http")
    end

    test "returns {:error, :not_found} on 404", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/@openfn/language-missing", fn conn ->
        Plug.Conn.resp(conn, 404, "")
      end)

      assert {:error, :not_found} =
               Registry.get_packument("@openfn/language-missing")
    end

    test "surfaces 5xx as {:error, {:http_status, status}}", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/@openfn/language-http", fn conn ->
        Plug.Conn.resp(conn, 502, "")
      end)

      assert {:error, {:http_status, 502}} =
               Registry.get_packument("@openfn/language-http")
    end
  end

  defp json_resp(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(status, Jason.encode!(body))
  end
end
