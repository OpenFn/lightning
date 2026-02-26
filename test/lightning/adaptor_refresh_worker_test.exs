defmodule Lightning.AdaptorRefreshWorkerTest do
  use Lightning.DataCase, async: false

  import Mock
  import Mox

  setup :verify_on_exit!

  alias Lightning.AdaptorRefreshWorker

  setup do
    # Redirect schemas_path to a tmp dir so refresh doesn't wipe
    # the tracked test fixtures in test/fixtures/schemas/
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "worker_schemas_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    previous_schemas_path = Application.get_env(:lightning, :schemas_path)
    Application.put_env(:lightning, :schemas_path, tmp_dir)

    on_exit(fn ->
      Application.put_env(:lightning, :schemas_path, previous_schemas_path)
      File.rm_rf(tmp_dir)
    end)

    :ok
  end

  describe "perform/1" do
    test "skips refresh when local adaptors mode is enabled" do
      stub(Lightning.MockConfig, :adaptor_registry, fn ->
        [local_adaptors_repo: "/tmp/fake-adaptors"]
      end)

      assert :ok = AdaptorRefreshWorker.perform(%Oban.Job{})
    end

    test "runs all refreshes and returns :ok" do
      stub(Lightning.MockConfig, :adaptor_registry, fn -> [] end)

      stub(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %Tesla.Env{status: 200, body: ""}}
      end)

      with_mock HTTPoison,
        get: fn _url, _headers, _opts ->
          {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{})}}
        end do
        assert :ok = AdaptorRefreshWorker.perform(%Oban.Job{})
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
