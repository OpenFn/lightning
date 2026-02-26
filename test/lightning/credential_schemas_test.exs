defmodule Lightning.CredentialSchemasTest do
  use Lightning.DataCase, async: false

  import Mock

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "credential_schemas_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    previous = Application.get_env(:lightning, :schemas_path)
    Application.put_env(:lightning, :schemas_path, tmp_dir)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:lightning, :schemas_path, previous),
        else: Application.delete_env(:lightning, :schemas_path)

      File.rm_rf(tmp_dir)
    end)

    %{schemas_path: tmp_dir}
  end

  describe "refresh/0" do
    test "returns error when npm fetch fails" do
      with_mock HTTPoison,
        get: fn _url, _headers, _opts ->
          {:error, %HTTPoison.Error{reason: :econnrefused}}
        end do
        assert {:error, :econnrefused} = Lightning.CredentialSchemas.refresh()
      end
    end

    test "returns error on non-200 npm response" do
      with_mock HTTPoison,
        get: fn _url, _headers, _opts ->
          {:ok, %HTTPoison.Response{status_code: 503, body: ""}}
        end do
        assert {:error, "NPM returned 503"} =
                 Lightning.CredentialSchemas.refresh()
      end
    end

    test "downloads schemas and returns count", %{schemas_path: schemas_path} do
      packages =
        Jason.encode!(%{
          "@openfn/language-http" => "read",
          "@openfn/language-salesforce" => "read",
          "@openfn/language-common" => "read",
          "@openfn/language-devtools" => "read"
        })

      schema_body = Jason.encode!(%{"type" => "object", "properties" => %{}})

      with_mock HTTPoison,
        get: fn url, _headers, _opts ->
          cond do
            String.contains?(url, "registry.npmjs.org") ->
              {:ok, %HTTPoison.Response{status_code: 200, body: packages}}

            String.contains?(url, "cdn.jsdelivr.net") ->
              {:ok, %HTTPoison.Response{status_code: 200, body: schema_body}}

            true ->
              {:ok, %HTTPoison.Response{status_code: 404, body: ""}}
          end
        end do
        assert {:ok, count} = Lightning.CredentialSchemas.refresh()

        # language-common and language-devtools are excluded by default
        # So only language-http and language-salesforce should be fetched
        assert count == 2

        assert File.exists?(Path.join(schemas_path, "http.json"))
        assert File.exists?(Path.join(schemas_path, "salesforce.json"))
        refute File.exists?(Path.join(schemas_path, "common.json"))
      end
    end

    test "wipes existing schemas before downloading new ones", %{
      schemas_path: schemas_path
    } do
      # Create a stale schema file that should be removed
      stale_path = Path.join(schemas_path, "stale-adaptor.json")
      File.write!(stale_path, ~s({"old": true}))

      packages =
        Jason.encode!(%{
          "@openfn/language-http" => "read"
        })

      schema_body = Jason.encode!(%{"type" => "object"})

      with_mock HTTPoison,
        get: fn url, _headers, _opts ->
          cond do
            String.contains?(url, "registry.npmjs.org") ->
              {:ok, %HTTPoison.Response{status_code: 200, body: packages}}

            String.contains?(url, "cdn.jsdelivr.net") ->
              {:ok, %HTTPoison.Response{status_code: 200, body: schema_body}}

            true ->
              {:ok, %HTTPoison.Response{status_code: 404, body: ""}}
          end
        end do
        assert {:ok, 1} = Lightning.CredentialSchemas.refresh()
        assert File.exists?(Path.join(schemas_path, "http.json"))
        refute File.exists?(stale_path), "stale schema file should be removed"
      end
    end

    test "handles individual schema download failures gracefully", %{
      schemas_path: schemas_path
    } do
      packages =
        Jason.encode!(%{
          "@openfn/language-http" => "read",
          "@openfn/language-salesforce" => "read"
        })

      with_mock HTTPoison,
        get: fn url, _headers, _opts ->
          cond do
            String.contains?(url, "registry.npmjs.org") ->
              {:ok, %HTTPoison.Response{status_code: 200, body: packages}}

            String.contains?(url, "language-http") ->
              {:ok,
               %HTTPoison.Response{
                 status_code: 200,
                 body: ~s({"type": "object"})
               }}

            String.contains?(url, "language-salesforce") ->
              {:ok, %HTTPoison.Response{status_code: 404, body: ""}}

            true ->
              {:ok, %HTTPoison.Response{status_code: 404, body: ""}}
          end
        end do
        assert {:ok, 1} = Lightning.CredentialSchemas.refresh()
        assert File.exists?(Path.join(schemas_path, "http.json"))
        refute File.exists?(Path.join(schemas_path, "salesforce.json"))
      end
    end
  end
end
