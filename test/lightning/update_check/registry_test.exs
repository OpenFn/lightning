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

    test "sends credentials as basic auth when fetching a token" do
      expected = "Basic " <> Base.encode64("robot:s3cret")

      mock(fn
        %{url: @tags_url, headers: headers} ->
          if List.keyfind(headers, "authorization", 0),
            do: json(%{"tags" => ["v1.0.0"]}),
            else: %Tesla.Env{
              status: 401,
              headers: [{"www-authenticate", @challenge}]
            }

        %{url: @realm, headers: headers} ->
          assert {"authorization", ^expected} =
                   List.keyfind(headers, "authorization", 0)

          json(%{"access_token" => "private"})
      end)

      assert {:ok, ["v1.0.0"], %{authorization: "Bearer private"}} =
               Registry.list_tags(
                 registry(username: "robot", password: "s3cret")
               )
    end

    test "answers a Basic challenge with the credentials" do
      expected = "Basic " <> Base.encode64("robot:s3cret")

      mock(fn %{url: @tags_url, headers: headers} ->
        case List.keyfind(headers, "authorization", 0) do
          {"authorization", ^expected} ->
            json(%{"tags" => ["v1.0.0"]})

          nil ->
            %Tesla.Env{
              status: 401,
              headers: [{"www-authenticate", ~s(Basic realm="Registry")}]
            }
        end
      end)

      assert {:ok, ["v1.0.0"], _registry} =
               Registry.list_tags(
                 registry(username: "robot", password: "s3cret")
               )
    end

    test "fails on a Basic challenge without credentials" do
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
