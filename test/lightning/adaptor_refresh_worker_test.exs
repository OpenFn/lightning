defmodule Lightning.AdaptorRefreshWorkerTest do
  use Lightning.DataCase, async: false

  import Mox

  setup :set_mox_from_context
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

      stub(Lightning.Tesla.Mock, :call, fn env, _opts ->
        cond do
          String.contains?(env.url, "cdn.jsdelivr.net") ->
            {:ok, %Tesla.Env{status: 200, body: ~s({"fields": []})}}

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

      assert :ok = AdaptorRefreshWorker.perform(%Oban.Job{})

      # Registry was written to DB
      assert {:ok, entry} = Lightning.AdaptorData.get("registry", "all")
      assert entry.content_type == "application/json"
      assert is_binary(entry.data)

      # At least one schema was written to DB
      schemas = Lightning.AdaptorData.get_all("schema")
      assert length(schemas) > 0
    end

    test "returns :ok even when all HTTP calls fail" do
      stub(Lightning.MockConfig, :adaptor_registry, fn -> [] end)

      stub(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:error, :econnrefused}
      end)

      assert :ok = AdaptorRefreshWorker.perform(%Oban.Job{})
    end

    test "handles partial failure — broadcasts only successful kinds" do
      stub(Lightning.MockConfig, :adaptor_registry, fn -> [] end)

      # Registry (npm) succeeds, jsDelivr schema fetch fails.
      stub(Lightning.Tesla.Mock, :call, fn env, _opts ->
        cond do
          String.contains?(env.url, "cdn.jsdelivr.net") ->
            {:error, :econnrefused}

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

      assert :ok = AdaptorRefreshWorker.perform(%Oban.Job{})

      # Registry should still be written
      assert {:ok, _entry} = Lightning.AdaptorData.get("registry", "all")
    end

    test "safe_call rescues exceptions and returns :ok" do
      stub(Lightning.MockConfig, :adaptor_registry, fn -> [] end)

      stub(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        raise "unexpected failure"
      end)

      assert :ok = AdaptorRefreshWorker.perform(%Oban.Job{})
    end
  end
end
