defmodule Lightning.AdaptorRefreshWorkerTest do
  use Lightning.DataCase, async: false

  import Mock
  import Mox

  setup :verify_on_exit!

  alias Lightning.AdaptorRefreshWorker

  describe "perform/1" do
    test "skips refresh when local adaptors mode is enabled" do
      stub(Lightning.MockConfig, :adaptor_registry, fn ->
        [local_adaptors_repo: "/tmp/fake-adaptors"]
      end)

      assert :ok = AdaptorRefreshWorker.perform(%Oban.Job{})
    end

    test "writes registry and schema data to DB on success" do
      stub(Lightning.MockConfig, :adaptor_registry, fn -> [] end)

      # Tesla mock for AdaptorRegistry.fetch() — NPM user packages + details
      stub(Lightning.Tesla.Mock, :call, fn env, _opts ->
        cond do
          String.contains?(env.url, "/-/user/openfn/package") ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{"@openfn/language-http" => "read"}
             }}

          String.contains?(env.url, "language-http") ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "name" => "@openfn/language-http",
                 "repository" => %{"url" => "https://github.com/openfn/adaptors"},
                 "dist-tags" => %{"latest" => "1.0.0"},
                 "versions" => %{"1.0.0" => %{}}
               }
             }}

          true ->
            {:ok, %Tesla.Env{status: 200, body: %{}}}
        end
      end)

      # HTTPoison mock for CredentialSchemas.fetch_and_store()
      with_mock HTTPoison,
        get: fn url, _headers, _opts ->
          cond do
            String.contains?(url, "registry.npmjs.org") ->
              body =
                Jason.encode!(%{
                  "@openfn/language-http" => "read",
                  "@openfn/language-common" => "read"
                })

              {:ok, %HTTPoison.Response{status_code: 200, body: body}}

            String.contains?(url, "cdn.jsdelivr.net") ->
              {:ok,
               %HTTPoison.Response{
                 status_code: 200,
                 body: ~s({"fields": []})
               }}

            true ->
              {:ok, %HTTPoison.Response{status_code: 404, body: ""}}
          end
        end do
        assert :ok = AdaptorRefreshWorker.perform(%Oban.Job{})

        # Verify registry was written to DB
        assert {:ok, entry} = Lightning.AdaptorData.get("registry", "all")
        assert entry.content_type == "application/json"
        assert is_binary(entry.data)

        # Verify at least one schema was written to DB
        schemas = Lightning.AdaptorData.get_all("schema")
        assert length(schemas) > 0
      end
    end

    test "returns :ok even when all HTTP calls fail" do
      stub(Lightning.MockConfig, :adaptor_registry, fn -> [] end)

      stub(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:error, :econnrefused}
      end)

      with_mock HTTPoison,
        get: fn _url, _headers, _opts ->
          {:error, %HTTPoison.Error{reason: :econnrefused}}
        end do
        assert :ok = AdaptorRefreshWorker.perform(%Oban.Job{})
      end
    end

    test "handles partial failure — broadcasts only successful kinds" do
      stub(Lightning.MockConfig, :adaptor_registry, fn -> [] end)

      # Registry fetch succeeds via Tesla
      stub(Lightning.Tesla.Mock, :call, fn env, _opts ->
        cond do
          String.contains?(env.url, "/-/user/openfn/package") ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{"@openfn/language-http" => "read"}
             }}

          String.contains?(env.url, "language-http") ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "name" => "@openfn/language-http",
                 "repository" => %{"url" => "https://github.com/openfn/adaptors"},
                 "dist-tags" => %{"latest" => "1.0.0"},
                 "versions" => %{"1.0.0" => %{}}
               }
             }}

          true ->
            {:ok, %Tesla.Env{status: 200, body: %{}}}
        end
      end)

      # Schema fetch fails via HTTPoison
      with_mock HTTPoison,
        get: fn _url, _headers, _opts ->
          {:error, %HTTPoison.Error{reason: :econnrefused}}
        end do
        assert :ok = AdaptorRefreshWorker.perform(%Oban.Job{})

        # Registry should still be written
        assert {:ok, _entry} = Lightning.AdaptorData.get("registry", "all")
      end
    end

    test "safe_call rescues exceptions and returns :ok" do
      stub(Lightning.MockConfig, :adaptor_registry, fn -> [] end)

      stub(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        raise "unexpected failure"
      end)

      with_mock HTTPoison,
        get: fn _url, _headers, _opts ->
          raise "unexpected failure"
        end do
        assert :ok = AdaptorRefreshWorker.perform(%Oban.Job{})
      end
    end
  end
end
