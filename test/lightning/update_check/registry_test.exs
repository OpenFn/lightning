defmodule Lightning.UpdateCheck.RegistryTest do
  use ExUnit.Case, async: true

  import Tesla.Mock

  alias Lightning.UpdateCheck.Registry

  @base "https://registry.example.com"
  @tags_url "#{@base}/v2/openfn/lightning/tags/list"
  @manifests_url "#{@base}/v2/openfn/lightning/manifests"
  @blobs_url "#{@base}/v2/openfn/lightning/blobs"
  @realm "https://auth.example.com/token"
  @challenge ~s(Bearer realm="#{@realm}",service="registry.example.com",scope="repository:openfn/lightning:pull")

  @image_config %{
    "Labels" => %{"org.opencontainers.image.version" => "v2.19.2"},
    "Env" => ["IMAGE_TAG=v2.19.2"]
  }

  defp registry(opts \\ []) do
    Registry.new(
      Keyword.merge(
        [registry: @base <> "/", repository: "openfn/lightning"],
        opts
      )
    )
  end

  defp authorized?(headers) do
    List.keyfind(headers, "authorization", 0) == {"authorization", "Bearer abc"}
  end

  defp challenge do
    %Tesla.Env{status: 401, headers: [{"www-authenticate", @challenge}]}
  end

  describe "image_config/2" do
    test "reads the config of the first real platform in an index" do
      mock(fn
        %{url: @realm} ->
          json(%{"token" => "abc"})

        %{url: "#{@manifests_url}/latest", headers: headers} ->
          assert {"accept", accept} = List.keyfind(headers, "accept", 0)
          assert accept =~ "application/vnd.oci.image.index.v1+json"

          if authorized?(headers) do
            json(%{
              "manifests" => [
                %{
                  "digest" => "sha256:attestation",
                  "platform" => %{"os" => "unknown", "architecture" => "unknown"}
                },
                %{
                  "digest" => "sha256:amd64",
                  "platform" => %{"os" => "linux", "architecture" => "amd64"}
                }
              ]
            })
          else
            challenge()
          end

        %{url: "#{@manifests_url}/sha256:amd64", headers: headers} ->
          assert authorized?(headers)
          json(%{"config" => %{"digest" => "sha256:config"}})

        %{url: "#{@blobs_url}/sha256:config", headers: headers} ->
          assert authorized?(headers)
          json(%{"architecture" => "amd64", "config" => @image_config})
      end)

      assert {:ok, @image_config, registry} =
               Registry.image_config(registry(), "latest")

      assert registry.authorization == "Bearer abc"
    end

    test "reads a single-platform image directly" do
      mock(fn
        %{url: "#{@manifests_url}/latest"} ->
          json(%{"config" => %{"digest" => "sha256:config"}})

        %{url: "#{@blobs_url}/sha256:config"} ->
          # Blobs aren't served as application/json.
          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "application/octet-stream"}],
            body: Jason.encode!(%{"config" => @image_config})
          }
      end)

      assert {:ok, @image_config, _registry} =
               Registry.image_config(registry(), "latest")
    end

    test "follows a blob redirect without sending the token off the registry" do
      mock(fn
        %{url: @realm} ->
          json(%{"token" => "abc"})

        %{url: "#{@manifests_url}/latest", headers: headers} ->
          if authorized?(headers),
            do: json(%{"config" => %{"digest" => "sha256:config"}}),
            else: challenge()

        %{url: "#{@blobs_url}/sha256:config"} ->
          %Tesla.Env{
            status: 307,
            headers: [{"location", "https://cdn.example.com/blob?sig=x"}]
          }

        %{url: "https://cdn.example.com/blob?sig=x", headers: headers} ->
          refute List.keyfind(headers, "authorization", 0)
          json(%{"config" => @image_config})
      end)

      assert {:ok, @image_config, _registry} =
               Registry.image_config(registry(), "latest")
    end

    test "returns nil for a missing tag" do
      mock(fn %{url: "#{@manifests_url}/nope"} -> %Tesla.Env{status: 404} end)

      assert {:ok, nil, _registry} = Registry.image_config(registry(), "nope")
    end

    test "fails on an index with no real platform" do
      mock(fn %{url: "#{@manifests_url}/latest"} ->
        json(%{
          "manifests" => [
            %{"digest" => "sha256:a", "platform" => %{"os" => "unknown"}}
          ]
        })
      end)

      assert Registry.image_config(registry(), "latest") ==
               {:error, :no_image_manifest}
    end

    test "reports unexpected statuses" do
      mock(fn %{url: "#{@manifests_url}/latest"} -> %Tesla.Env{status: 503} end)

      assert Registry.image_config(registry(), "latest") ==
               {:error, {:unexpected_status, 503}}
    end
  end

  describe "list_tags/1" do
    test "answers a Bearer challenge with an anonymous token and retries" do
      mock(fn
        %{url: @tags_url, query: [{"n", "1000"}], headers: headers} ->
          if authorized?(headers),
            do: json(%{"tags" => ["v2.19.2", "latest"]}),
            else: challenge()

        %{url: @realm, query: query, headers: headers} ->
          assert {"service", "registry.example.com"} in query
          assert {"scope", "repository:openfn/lightning:pull"} in query
          refute List.keyfind(headers, "authorization", 0)
          json(%{"token" => "abc"})
      end)

      assert {:ok, ["v2.19.2", "latest"], registry} =
               Registry.list_tags(registry())

      assert registry.authorization == "Bearer abc"
    end

    test "fails on a Basic challenge" do
      mock(fn %{url: @tags_url} ->
        %Tesla.Env{
          status: 401,
          headers: [{"www-authenticate", ~s(Basic realm="x")}]
        }
      end)

      assert Registry.list_tags(registry()) == {:error, :unauthorized}
    end

    test "lists one page and warns when the registry has more" do
      mock(fn %{url: @tags_url} ->
        json(%{"tags" => ["v1.0.0"]},
          headers: [
            {"link",
             ~s(<https://elsewhere.example.com/v2/openfn/lightning/tags/list?last=v1.0.0>; rel="next")}
          ]
        )
      end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, ["v1.0.0"], _registry} = Registry.list_tags(registry())
        end)

      assert log =~ "Listed only the first 1000 tags of openfn/lightning"
    end

    test "reports unexpected statuses" do
      mock(fn %{url: @tags_url} -> %Tesla.Env{status: 503} end)

      assert Registry.list_tags(registry()) ==
               {:error, {:unexpected_status, 503}}
    end
  end

  describe "parse_challenge/1" do
    test "splits the scheme and its parameters" do
      assert Registry.parse_challenge(@challenge) ==
               {"bearer",
                %{
                  "realm" => @realm,
                  "service" => "registry.example.com",
                  "scope" => "repository:openfn/lightning:pull"
                }}

      assert Registry.parse_challenge(nil) == nil
    end
  end
end
