defmodule Lightning.UpdateCheck.RegistryTest do
  use ExUnit.Case, async: true

  import Tesla.Mock

  alias Lightning.UpdateCheck.Registry

  @base "https://registry.example.com"
  @tags_url "#{@base}/v2/openfn/lightning/tags/list"
  @realm "https://auth.example.com/token"
  @challenge ~s(Bearer realm="#{@realm}",service="registry.example.com",scope="repository:openfn/lightning:pull")

  defp registry(opts \\ []) do
    Registry.new(
      Keyword.merge(
        [registry: @base <> "/", repository: "openfn/lightning"],
        opts
      )
    )
  end

  describe "list_tags/1" do
    test "answers a Bearer challenge with an anonymous token and retries" do
      mock(fn
        %{url: @tags_url, headers: headers} ->
          case List.keyfind(headers, "authorization", 0) do
            {"authorization", "Bearer abc"} ->
              json(%{"tags" => ["v2.19.2", "latest"]})

            nil ->
              %Tesla.Env{
                status: 401,
                headers: [{"www-authenticate", @challenge}]
              }
          end

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

    test "follows Link pagination" do
      mock(fn
        %{url: @tags_url, query: [{"n", "1000"}]} ->
          json(%{"tags" => ["v1.0.0"]},
            headers: [
              {"link",
               ~s(</v2/openfn/lightning/tags/list?last=v1.0.0&n=1000>; rel="next")}
            ]
          )

        %{url: @tags_url, query: [{"last", "v1.0.0"}, {"n", "1000"}]} ->
          json(%{"tags" => ["v1.1.0"]})
      end)

      assert {:ok, ["v1.0.0", "v1.1.0"], _registry} =
               Registry.list_tags(registry())
    end

    test "stops after 20 pages and warns that tags were left out" do
      # Every page says there's another.
      mock(fn %{url: @tags_url} ->
        json(%{"tags" => ["v1.0.0"]},
          headers: [
            {"link",
             ~s(</v2/openfn/lightning/tags/list?last=v1.0.0&n=1000>; rel="next")}
          ]
        )
      end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, tags, _registry} = Registry.list_tags(registry())
          assert length(tags) == 20
        end)

      assert log =~ "Stopped listing tags for openfn/lightning after 20 pages"
    end

    test "reports unexpected statuses" do
      mock(fn %{url: @tags_url} -> %Tesla.Env{status: 503} end)

      assert Registry.list_tags(registry()) ==
               {:error, {:unexpected_status, 503}}
    end
  end

  describe "digest/2" do
    test "reads the content digest of a tag" do
      mock(fn %{
                method: :head,
                url: "#{@base}/v2/openfn/lightning/manifests/latest",
                headers: headers
              } ->
        assert {"accept", accept} = List.keyfind(headers, "accept", 0)
        assert accept =~ "application/vnd.oci.image.index.v1+json"

        %Tesla.Env{
          status: 200,
          headers: [{"docker-content-digest", "sha256:abc"}]
        }
      end)

      assert {:ok, "sha256:abc", _registry} =
               Registry.digest(registry(), "latest")
    end

    test "returns nil for a missing tag" do
      mock(fn %{method: :head} -> %Tesla.Env{status: 404} end)

      assert {:ok, nil, _registry} = Registry.digest(registry(), "nope")
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
