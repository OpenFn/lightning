defmodule Lightning.CredentialSchemasTest do
  use Lightning.DataCase, async: false

  import Mox

  setup :set_mox_from_context
  setup :verify_on_exit!

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
      stub(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:error, :econnrefused}
      end)

      assert {:error, :econnrefused} = Lightning.CredentialSchemas.refresh()
    end

    test "returns error on non-200 npm response" do
      stub(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %Tesla.Env{status: 503, body: ""}}
      end)

      assert {:error, "NPM returned 503"} =
               Lightning.CredentialSchemas.refresh()
    end

    test "downloads schemas and returns count", %{schemas_path: schemas_path} do
      packages = %{
        "@openfn/language-http" => "read",
        "@openfn/language-salesforce" => "read",
        "@openfn/language-common" => "read",
        "@openfn/language-devtools" => "read"
      }

      schema_body = ~s({"type":"object","properties":{}})

      stub(Lightning.Tesla.Mock, :call, fn env, _opts ->
        cond do
          String.contains?(env.url, "registry.npmjs.org") ->
            {:ok, %Tesla.Env{status: 200, body: packages}}

          String.contains?(env.url, "cdn.jsdelivr.net") ->
            {:ok, %Tesla.Env{status: 200, body: schema_body}}

          true ->
            {:ok, %Tesla.Env{status: 404, body: ""}}
        end
      end)

      assert {:ok, count} = Lightning.CredentialSchemas.refresh()

      # language-common and language-devtools are excluded by default
      assert count == 2

      assert File.exists?(Path.join(schemas_path, "http.json"))
      assert File.exists?(Path.join(schemas_path, "salesforce.json"))
      refute File.exists?(Path.join(schemas_path, "common.json"))
    end

    test "wipes existing schemas before downloading new ones", %{
      schemas_path: schemas_path
    } do
      stale_path = Path.join(schemas_path, "stale-adaptor.json")
      File.write!(stale_path, ~s({"old": true}))

      packages = %{"@openfn/language-http" => "read"}
      schema_body = ~s({"type":"object"})

      stub(Lightning.Tesla.Mock, :call, fn env, _opts ->
        cond do
          String.contains?(env.url, "registry.npmjs.org") ->
            {:ok, %Tesla.Env{status: 200, body: packages}}

          String.contains?(env.url, "cdn.jsdelivr.net") ->
            {:ok, %Tesla.Env{status: 200, body: schema_body}}

          true ->
            {:ok, %Tesla.Env{status: 404, body: ""}}
        end
      end)

      assert {:ok, 1} = Lightning.CredentialSchemas.refresh()
      assert File.exists?(Path.join(schemas_path, "http.json"))
      refute File.exists?(stale_path), "stale schema file should be removed"
    end

    test "handles individual schema download failures gracefully", %{
      schemas_path: schemas_path
    } do
      packages = %{
        "@openfn/language-http" => "read",
        "@openfn/language-salesforce" => "read"
      }

      stub(Lightning.Tesla.Mock, :call, fn env, _opts ->
        cond do
          String.contains?(env.url, "registry.npmjs.org") ->
            {:ok, %Tesla.Env{status: 200, body: packages}}

          String.contains?(env.url, "language-http") ->
            {:ok, %Tesla.Env{status: 200, body: ~s({"type": "object"})}}

          String.contains?(env.url, "language-salesforce") ->
            {:ok, %Tesla.Env{status: 404, body: ""}}

          true ->
            {:ok, %Tesla.Env{status: 404, body: ""}}
        end
      end)

      assert {:ok, 1} = Lightning.CredentialSchemas.refresh()
      assert File.exists?(Path.join(schemas_path, "http.json"))
      refute File.exists?(Path.join(schemas_path, "salesforce.json"))
    end
  end
end
