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
  end
end
