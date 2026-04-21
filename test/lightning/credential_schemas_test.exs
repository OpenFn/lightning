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

  describe "fetch_and_store/0 with local adaptors repo" do
    setup do
      repo_dir =
        Path.join(
          System.tmp_dir!(),
          "schemas_local_test_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(repo_dir)

      previous_config =
        Application.get_env(:lightning, Lightning.AdaptorRegistry)

      Application.put_env(
        :lightning,
        Lightning.AdaptorRegistry,
        Keyword.put(previous_config || [], :local_adaptors_repo, repo_dir)
      )

      stub(Lightning.MockConfig, :adaptor_registry, fn ->
        [local_adaptors_repo: repo_dir]
      end)

      on_exit(fn ->
        Application.put_env(
          :lightning,
          Lightning.AdaptorRegistry,
          previous_config || []
        )

        File.rm_rf(repo_dir)
      end)

      %{repo_dir: repo_dir}
    end

    test "reads schema JSON from local repo without hitting the network", %{
      repo_dir: repo_dir
    } do
      http_body = ~s({"from":"local","fields":[]})

      for pkg <- ["http", "salesforce"] do
        dir = Path.join([repo_dir, "packages", pkg])
        File.mkdir_p!(dir)
        File.write!(Path.join(dir, "configuration-schema.json"), http_body)
      end

      # No Tesla stub — must not hit the network at all
      assert {:ok, 2} = Lightning.CredentialSchemas.fetch_and_store()

      schemas = Lightning.AdaptorData.get_all("schema")
      assert Enum.map(schemas, & &1.key) |> Enum.sort() == ["http", "salesforce"]
      assert Enum.all?(schemas, &(&1.data == http_body))
    end

    test "falls back to jsDelivr for packages without a local schema", %{
      repo_dir: repo_dir
    } do
      # Only language-http has a local schema file
      http_dir = Path.join([repo_dir, "packages", "http"])
      File.mkdir_p!(http_dir)

      File.write!(
        Path.join(http_dir, "configuration-schema.json"),
        ~s({"source":"local"})
      )

      # language-salesforce package dir exists but no schema file → fallback
      File.mkdir_p!(Path.join([repo_dir, "packages", "salesforce"]))

      # Tesla stub serves only the fallback call
      stub(Lightning.Tesla.Mock, :call, fn env, _opts ->
        cond do
          String.contains?(env.url, "language-salesforce") ->
            {:ok, %Tesla.Env{status: 200, body: ~s({"source":"jsdelivr"})}}

          true ->
            {:ok, %Tesla.Env{status: 404, body: ""}}
        end
      end)

      assert {:ok, 2} = Lightning.CredentialSchemas.fetch_and_store()

      schemas =
        Lightning.AdaptorData.get_all("schema")
        |> Map.new(fn s -> {s.key, s.data} end)

      assert schemas["http"] == ~s({"source":"local"})
      assert schemas["salesforce"] == ~s({"source":"jsdelivr"})
    end

    test "skips excluded adaptors even when they exist in the local repo", %{
      repo_dir: repo_dir
    } do
      # "common" is in @default_excluded_adaptors
      for pkg <- ["http", "common", "devtools"] do
        dir = Path.join([repo_dir, "packages", pkg])
        File.mkdir_p!(dir)
        File.write!(Path.join(dir, "configuration-schema.json"), ~s({}))
      end

      assert {:ok, 1} = Lightning.CredentialSchemas.fetch_and_store()

      keys =
        Lightning.AdaptorData.get_all("schema")
        |> Enum.map(& &1.key)
        |> Enum.sort()

      assert keys == ["http"]
    end
  end
end
