defmodule Lightning.UpdateCheckTest do
  use ExUnit.Case, async: true

  import Tesla.Mock

  alias Lightning.UpdateCheck

  @base "https://registry-1.docker.io"
  @config [registry: @base, repository: "openfn/lightning", tag: "latest"]
  @worker_base "https://workers.example.com"

  @worker_config @config ++
                   [
                     worker_registry: @base,
                     worker_repository: "openfn/ws-worker"
                   ]

  # Serves each `{registry, repository}` in `images` as a single-platform
  # image at `latest`. An image is a map of:
  #
  # - `:config` - the image's runtime config, or `nil` for no `latest` tag
  # - `:tags` - the repository's tag list
  # - `:status` - answers every request with this status instead
  defp mock_images(images) do
    mock(fn %{url: url} ->
      Enum.find_value(images, fn {{base, repository}, image} ->
        prefix = "#{base}/v2/#{repository}/"

        if String.starts_with?(url, prefix),
          do: respond(String.replace_prefix(url, prefix, ""), image)
      end)
    end)
  end

  defp respond(_path, %{status: status}), do: %Tesla.Env{status: status}

  defp respond("manifests/latest", %{config: nil}),
    do: %Tesla.Env{status: 404}

  defp respond("manifests/latest", _image),
    do: json(%{"config" => %{"digest" => "sha256:config"}})

  defp respond("blobs/sha256:config", %{config: config}),
    do: json(%{"config" => config})

  defp respond("tags/list", image), do: json(%{"tags" => image[:tags] || []})

  defp app(image), do: %{{@base, "openfn/lightning"} => image}

  defp labelled(version),
    do: %{
      config: %{"Labels" => %{"org.opencontainers.image.version" => version}}
    }

  describe "check/2" do
    test "the latest release is the version label of the channel tag's image" do
      mock_images(app(labelled("2.19.2")))

      assert {:ok, status} = UpdateCheck.check(@config, "2.19.1")

      assert %{
               current: "2.19.1",
               latest: "2.19.2",
               latest_tag: "2.19.2",
               update_available?: true,
               instructions_url:
                 "https://docs.openfn.org/documentation/deploy/options#technical-guidelines"
             } = status
    end

    test "reads IMAGE_TAG from images built before the label" do
      mock_images(
        app(%{
          config: %{
            "Labels" => %{"commit" => "5f868a4"},
            "Env" => ["BRANCH=", "IMAGE_TAG=v2.19.2"]
          }
        })
      )

      assert {:ok, %{latest: "2.19.2", update_available?: false}} =
               UpdateCheck.check(@config, "2.19.2")
    end

    test "prefers the label to IMAGE_TAG" do
      mock_images(
        app(%{
          config: %{
            "Labels" => %{"org.opencontainers.image.version" => "2.19.3"},
            "Env" => ["IMAGE_TAG=v2.19.2"]
          }
        })
      )

      assert {:ok, %{latest: "2.19.3"}} = UpdateCheck.check(@config, "2.19.2")
    end

    test "falls back to the newest full-release tag when the image has no version" do
      mock_images(
        app(%{
          config: %{"Env" => ["IMAGE_TAG="]},
          tags: ["2.18.0", "2.19.2", "2.20.0-pre", "edge"]
        })
      )

      assert {:ok, %{latest: "2.19.2", latest_tag: "2.19.2"}} =
               UpdateCheck.check(@config, "2.18.0")
    end

    test "falls back across old v-prefixed tags and new unprefixed ones" do
      mock_images(
        app(%{config: nil, tags: ["v2.18.0", "v2.19.2", "2.19.3", "2.20.0-pre"]})
      )

      assert {:ok, %{latest: "2.19.3", latest_tag: "2.19.3"}} =
               UpdateCheck.check(@config, "2.18.0")
    end

    test "reads a v-prefixed version label from older images" do
      mock_images(app(labelled("v2.19.2")))

      assert {:ok, %{latest: "2.19.2", latest_tag: "v2.19.2"}} =
               UpdateCheck.check(@config, "2.19.1")
    end

    test "falls back to the newest full-release tag when there is no channel tag" do
      mock_images(app(%{config: nil, tags: ["2.18.0", "2.19.2"]}))

      assert {:ok, %{latest: "2.19.2", update_available?: true}} =
               UpdateCheck.check(@config, "2.18.0")
    end

    test "a pre-release build ahead of the latest release is not behind" do
      mock_images(app(labelled("2.19.2")))

      assert {:ok, %{update_available?: false}} =
               UpdateCheck.check(@config, "2.20.0-pre")
    end

    test "uses a configured instructions URL" do
      mock_images(app(labelled("2.19.3")))

      config =
        Keyword.put(@config, :instructions_url, "https://example.com/upgrade")

      assert {:ok, status} = UpdateCheck.check(config, "2.19.2")
      assert status.instructions_url == "https://example.com/upgrade"
    end

    test "fails when the channel tag's image isn't a full release" do
      for version <- ["edge", "2.20.0-pre"] do
        mock_images(app(labelled(version)))

        assert UpdateCheck.check(@config, "2.19.1") ==
                 {:error, :no_release_found}
      end
    end

    test "fails when falling back and there are no full releases" do
      mock_images(app(%{config: nil, tags: ["latest", "edge", "2.20.0-pre"]}))

      assert UpdateCheck.check(@config, "2.19.1") ==
               {:error, :no_release_found}
    end

    test "passes registry errors through" do
      mock_images(app(%{status: 500}))

      assert UpdateCheck.check(@config, "2.19.2") ==
               {:error, {:unexpected_status, 500}}
    end

    test "leaves workers unchecked without a worker repository" do
      mock_images(app(labelled("2.19.2")))

      assert {:ok, %{worker: nil}} = UpdateCheck.check(@config, "2.19.2")
    end
  end

  describe "check/2 with a worker repository" do
    test "reads the worker release from its image's version label" do
      mock_images(
        app(labelled("2.19.2"))
        |> Map.put({@base, "openfn/ws-worker"}, labelled("1.30.0"))
      )

      assert {:ok, %{worker: worker}} =
               UpdateCheck.check(@worker_config, "2.19.2")

      assert worker == %{
               latest: "1.30.0",
               latest_tag: "1.30.0",
               registry: @base,
               repository: "openfn/ws-worker"
             }
    end

    test "falls back to worker tags while worker images carry no version" do
      mock_images(
        app(labelled("2.19.2"))
        |> Map.put({@base, "openfn/ws-worker"}, %{
          config: %{"Env" => ["NODE_VERSION=24.22.1"]},
          tags: ["latest", "1.29.6", "1.30.0", "1.31.0-next"]
        })
      )

      assert {:ok, %{worker: %{latest: "1.30.0", latest_tag: "1.30.0"}}} =
               UpdateCheck.check(@worker_config, "2.19.2")
    end

    test "checks workers against the worker registry, not the app's" do
      mock_images(
        app(labelled("2.19.2"))
        |> Map.put({@worker_base, "openfn/ws-worker"}, labelled("1.30.0"))
      )

      config = Keyword.put(@worker_config, :worker_registry, @worker_base)

      assert {:ok, %{worker: %{latest: "1.30.0", registry: @worker_base}}} =
               UpdateCheck.check(config, "2.19.2")
    end

    test "a failed worker lookup doesn't fail the check" do
      mock_images(
        app(labelled("2.19.2"))
        |> Map.put({@base, "openfn/ws-worker"}, %{status: 500})
      )

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, %{latest: "2.19.2", worker: nil}} =
                   UpdateCheck.check(@worker_config, "2.19.2")
        end)

      assert log =~ "Worker update check failed"
    end

    test "no worker release found leaves workers unchecked" do
      mock_images(
        app(labelled("2.19.2"))
        |> Map.put({@base, "openfn/ws-worker"}, %{config: nil, tags: ["latest"]})
      )

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, %{worker: nil}} =
                   UpdateCheck.check(@worker_config, "2.19.2")
        end)

      assert log =~ "Worker update check failed: :no_release_found"
    end
  end

  describe "worker_outdated?/2 and update_available?/2" do
    @status %{update_available?: false, worker: %{latest: "1.30.0"}}

    test "a worker behind the latest release is outdated" do
      assert UpdateCheck.worker_outdated?(@status, "1.29.6")
      refute UpdateCheck.worker_outdated?(@status, "1.30.0")
      refute UpdateCheck.worker_outdated?(@status, "1.31.0-next")
    end

    test "a worker version with a leading v is compared the same way" do
      assert UpdateCheck.worker_outdated?(@status, "v1.29.6")
      refute UpdateCheck.worker_outdated?(@status, "v1.30.0")
    end

    test "a worker without a version is outdated" do
      assert UpdateCheck.worker_outdated?(@status, nil)
      assert UpdateCheck.update_available?(@status, ["1.30.0", nil])
    end

    test "nothing is outdated without a worker release" do
      refute UpdateCheck.worker_outdated?(%{@status | worker: nil}, nil)
      refute UpdateCheck.worker_outdated?(%{@status | worker: nil}, "1.0.0")
      refute UpdateCheck.worker_outdated?(nil, nil)
      refute UpdateCheck.worker_outdated?(nil, "1.0.0")
    end

    test "an update is available for the app or any connected worker" do
      refute UpdateCheck.update_available?(nil, ["1.0.0"])
      refute UpdateCheck.update_available?(@status, ["1.30.0"])
      assert UpdateCheck.update_available?(@status, ["1.30.0", "1.29.6"])

      assert UpdateCheck.update_available?(
               %{@status | update_available?: true},
               []
             )
    end
  end
end
