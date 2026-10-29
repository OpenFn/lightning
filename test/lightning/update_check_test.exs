defmodule Lightning.UpdateCheckTest do
  use ExUnit.Case, async: true

  import Tesla.Mock

  alias Lightning.UpdateCheck

  @base "https://registry-1.docker.io"
  @config [registry: @base, repository: "openfn/lightning", tag: "latest"]

  defp mock_registry(tags, digests) do
    mock(fn
      %{method: :get, url: "#{@base}/v2/openfn/lightning/tags/list"} ->
        json(%{"tags" => tags})

      %{method: :head, url: "#{@base}/v2/openfn/lightning/manifests/" <> tag} ->
        case Map.fetch(digests, tag) do
          {:ok, digest} ->
            %Tesla.Env{status: 200, headers: [{"docker-content-digest", digest}]}

          :error ->
            %Tesla.Env{status: 404}
        end
    end)
  end

  describe "check/2" do
    test "the latest release is the stable tag sharing the channel tag's digest" do
      mock_registry(
        ["edge", "latest", "v2.19.1", "v2.19.2", "v2.20.0-pre"],
        %{
          "latest" => "sha256:b",
          "v2.19.1" => "sha256:a",
          "v2.19.2" => "sha256:b",
          "v2.20.0-pre" => "sha256:c"
        }
      )

      assert {:ok, status} = UpdateCheck.check(@config, "2.19.1")

      assert %{
               current: "2.19.1",
               latest: "2.19.2",
               latest_tag: "v2.19.2",
               update_available?: true,
               instructions_url:
                 "https://docs.openfn.org/documentation/deploy/options#technical-guidelines"
             } = status
    end

    test "ignores a newer stable tag that the channel tag doesn't point at" do
      mock_registry(
        ["latest", "v2.19.2", "v2.20.0"],
        %{
          "latest" => "sha256:b",
          "v2.19.2" => "sha256:b",
          "v2.20.0" => "sha256:x"
        }
      )

      assert {:ok, %{latest: "2.19.2", update_available?: false}} =
               UpdateCheck.check(@config, "2.19.2")
    end

    test "falls back to the newest stable tag when there is no channel tag" do
      mock_registry(["v2.18.0", "v2.19.2", "edge"], %{})

      assert {:ok, %{latest: "2.19.2", update_available?: true}} =
               UpdateCheck.check(@config, "2.18.0")
    end

    test "a pre-release build ahead of the latest release is not behind" do
      mock_registry(["latest", "v2.19.2"], %{
        "latest" => "sha256:b",
        "v2.19.2" => "sha256:b"
      })

      assert {:ok, %{update_available?: false}} =
               UpdateCheck.check(@config, "2.20.0-pre")
    end

    test "uses a configured instructions URL" do
      config = [
        registry: "https://registry.example.com",
        repository: "openfn/lightning-private",
        tag: "latest",
        instructions_url: "https://example.com/upgrade"
      ]

      mock(fn %{method: :get} -> json(%{"tags" => ["v2.19.3"]}) end)

      assert {:ok, status} = UpdateCheck.check(config, "2.19.2")
      assert status.instructions_url == "https://example.com/upgrade"
    end

    test "passes registry errors through" do
      mock(fn %{method: :get} -> %Tesla.Env{status: 500} end)

      assert UpdateCheck.check(@config, "2.19.2") ==
               {:error, {:unexpected_status, 500}}
    end

    test "leaves workers unchecked without a worker repository" do
      mock_registry(["v2.19.2"], %{})

      assert {:ok, %{worker: nil}} = UpdateCheck.check(@config, "2.19.2")
    end
  end

  describe "check/2 with a worker repository" do
    @worker_config @config ++ [worker_repository: "openfn/ws-worker"]

    test "finds the latest worker release the same way" do
      mock(fn
        %{method: :get, url: "#{@base}/v2/openfn/lightning/tags/list"} ->
          json(%{"tags" => ["v2.19.2"]})

        %{method: :get, url: "#{@base}/v2/openfn/ws-worker/tags/list"} ->
          json(%{"tags" => ["latest", "v1.29.6", "v1.30.0", "v1.31.0-next"]})

        %{method: :head, url: "#{@base}/v2/openfn/ws-worker/manifests/" <> tag} ->
          digest = if tag in ["latest", "v1.30.0"], do: "sha256:w", else: "x"
          %Tesla.Env{status: 200, headers: [{"docker-content-digest", digest}]}
      end)

      assert {:ok, %{worker: worker}} =
               UpdateCheck.check(@worker_config, "2.19.2")

      assert worker == %{
               latest: "1.30.0",
               latest_tag: "v1.30.0",
               registry: @base,
               repository: "openfn/ws-worker"
             }
    end

    test "a failed worker lookup doesn't fail the check" do
      mock(fn
        %{method: :get, url: "#{@base}/v2/openfn/lightning/tags/list"} ->
          json(%{"tags" => ["v2.19.2"]})

        %{method: :get, url: "#{@base}/v2/openfn/ws-worker/tags/list"} ->
          %Tesla.Env{status: 500}
      end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, %{latest: "2.19.2", worker: nil}} =
                   UpdateCheck.check(@worker_config, "2.19.2")
        end)

      assert log =~ "Worker update check failed"
    end
  end

  describe "worker_outdated?/2 and update_available?/2" do
    @status %{update_available?: false, worker: %{latest: "1.30.0"}}

    test "a worker behind the latest release is outdated" do
      assert UpdateCheck.worker_outdated?(@status, "1.29.6")
      refute UpdateCheck.worker_outdated?(@status, "1.30.0")
      refute UpdateCheck.worker_outdated?(@status, "1.31.0-next")
    end

    test "a worker without a version, or no worker release, is never outdated" do
      refute UpdateCheck.worker_outdated?(@status, nil)
      refute UpdateCheck.worker_outdated?(%{@status | worker: nil}, "1.0.0")
      refute UpdateCheck.worker_outdated?(nil, "1.0.0")
    end

    test "an update is available for the app or any connected worker" do
      refute UpdateCheck.update_available?(nil, ["1.0.0"])
      refute UpdateCheck.update_available?(@status, ["1.30.0", nil])
      assert UpdateCheck.update_available?(@status, ["1.30.0", "1.29.6"])

      assert UpdateCheck.update_available?(
               %{@status | update_available?: true},
               []
             )
    end
  end
end
