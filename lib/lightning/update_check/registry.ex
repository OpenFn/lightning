defmodule Lightning.UpdateCheck.Registry do
  @moduledoc """
  Minimal client for the OCI Distribution API, enough to list a repository's
  tags and read the digest a tag points at. Works with Docker Hub, GHCR,
  Harbor and other registries that implement the spec.

  Authentication follows the registry's `WWW-Authenticate` challenge. A
  `Bearer` challenge is answered by fetching a token from its realm, sending
  the configured username and password as basic auth when there are any. A
  `Basic` challenge is answered with the credentials directly. The resulting
  `authorization` header is kept on the struct, so callers thread the
  returned struct through later calls and authenticate once per check.

  No setting supplies a username or password yet, so every check fetches an
  anonymous token, which is all public Docker Hub repositories need. The
  credential handling is here so an access key can be added later.
  """

  @manifest_types Enum.join(
                    [
                      "application/vnd.oci.image.index.v1+json",
                      "application/vnd.oci.image.manifest.v1+json",
                      "application/vnd.docker.distribution.manifest.list.v2+json",
                      "application/vnd.docker.distribution.manifest.v2+json"
                    ],
                    ", "
                  )

  @max_pages 20
  @page_size 1000

  defstruct [:base_url, :repository, :username, :password, :authorization]

  @type t :: %__MODULE__{
          base_url: String.t(),
          repository: String.t(),
          username: String.t() | nil,
          password: String.t() | nil,
          authorization: String.t() | nil
        }

  @doc """
  Builds a client from the `:registry`, `:repository`, `:username` and
  `:password` options.
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      base_url: opts |> Keyword.fetch!(:registry) |> String.trim_trailing("/"),
      repository: Keyword.fetch!(opts, :repository),
      username: blank_to_nil(opts[:username]),
      password: blank_to_nil(opts[:password])
    }
  end

  @doc """
  Lists every tag in the repository, following `Link` pagination.
  """
  @spec list_tags(t()) :: {:ok, [String.t()], t()} | {:error, term()}
  def list_tags(%__MODULE__{} = registry) do
    path = "/v2/#{registry.repository}/tags/list"
    list_tags(registry, {path, [{"n", to_string(@page_size)}]}, [], @max_pages)
  end

  defp list_tags(registry, _page, acc, 0), do: {:ok, acc, registry}

  defp list_tags(registry, {path, query}, acc, pages_left) do
    case request(registry, method: :get, url: path, query: query) do
      {:ok, %Tesla.Env{status: 200, body: body} = env, registry} ->
        tags = acc ++ (decode(body)["tags"] || [])

        case next_page(env) do
          nil -> {:ok, tags, registry}
          next -> list_tags(registry, next, tags, pages_left - 1)
        end

      {:ok, %Tesla.Env{status: status}, _registry} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Reads the content digest of `tag`, or `nil` when the tag doesn't exist.
  """
  @spec digest(t(), String.t()) ::
          {:ok, String.t() | nil, t()} | {:error, term()}
  def digest(%__MODULE__{} = registry, tag) do
    path = "/v2/#{registry.repository}/manifests/#{tag}"

    case request(registry,
           method: :head,
           url: path,
           headers: [{"accept", @manifest_types}]
         ) do
      {:ok, %Tesla.Env{status: 200} = env, registry} ->
        {:ok, Tesla.get_header(env, "docker-content-digest"), registry}

      {:ok, %Tesla.Env{status: 404}, registry} ->
        {:ok, nil, registry}

      {:ok, %Tesla.Env{status: status}, _registry} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(registry, request) do
    case send_request(registry, request) do
      {:ok, %Tesla.Env{status: 401} = env} when is_nil(registry.authorization) ->
        with {:ok, authorization} <- authorize(registry, env) do
          registry = %{registry | authorization: authorization}

          case send_request(registry, request) do
            {:ok, env} -> {:ok, env, registry}
            {:error, reason} -> {:error, reason}
          end
        end

      {:ok, env} ->
        {:ok, env, registry}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_request(registry, request) do
    headers = Keyword.get(request, :headers, [])

    headers =
      if registry.authorization,
        do: [{"authorization", registry.authorization} | headers],
        else: headers

    Tesla.request(client(registry), Keyword.put(request, :headers, headers))
  end

  defp authorize(registry, env) do
    case parse_challenge(Tesla.get_header(env, "www-authenticate")) do
      {"bearer", params} -> fetch_token(registry, params)
      {"basic", _params} -> basic_authorization(registry)
      _other -> {:error, :unauthorized}
    end
  end

  defp fetch_token(registry, %{"realm" => realm} = params) do
    query = params |> Map.take(["service", "scope"]) |> Enum.to_list()

    headers =
      case basic_authorization(registry) do
        {:ok, authorization} -> [{"authorization", authorization}]
        {:error, _} -> []
      end

    case Tesla.get(client(registry), realm, query: query, headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        case decode(body) do
          %{"token" => token} when is_binary(token) ->
            {:ok, "Bearer " <> token}

          %{"access_token" => token} when is_binary(token) ->
            {:ok, "Bearer " <> token}

          _other ->
            {:error, :invalid_token_response}
        end

      {:ok, %Tesla.Env{status: status}} ->
        {:error, {:token_request_failed, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_token(_registry, _params), do: {:error, :unauthorized}

  defp basic_authorization(%{username: username, password: password})
       when is_binary(username) and is_binary(password) do
    {:ok, "Basic " <> Base.encode64("#{username}:#{password}")}
  end

  defp basic_authorization(_registry), do: {:error, :unauthorized}

  @doc false
  # `Bearer realm="https://auth.docker.io/token",service="registry.docker.io"`
  # becomes `{"bearer", %{"realm" => ..., "service" => ...}}`.
  @spec parse_challenge(String.t() | nil) :: {String.t(), map()} | nil
  def parse_challenge(nil), do: nil

  def parse_challenge(header) do
    case String.split(String.trim(header), " ", parts: 2) do
      [scheme | rest] ->
        params =
          ~r/([A-Za-z_]+)="([^"]*)"/
          |> Regex.scan(Enum.join(rest))
          |> Map.new(fn [_match, key, value] ->
            {String.downcase(key), value}
          end)

        {String.downcase(scheme), params}

      [] ->
        nil
    end
  end

  # `Link: </v2/openfn/lightning/tags/list?last=v2.1.0&n=1000>; rel="next"`
  # becomes `{"/v2/openfn/lightning/tags/list", [{"last", "v2.1.0"}, {"n", "1000"}]}`.
  defp next_page(env) do
    with link when is_binary(link) <- Tesla.get_header(env, "link"),
         [_, url] <- Regex.run(~r/<([^>]+)>\s*;\s*rel="?next"?/, link) do
      uri = URI.parse(url)
      query = URI.query_decoder(uri.query || "") |> Enum.to_list()

      # Usually a path on the same registry, but an absolute URL is allowed.
      {URI.to_string(%{uri | query: nil}), query}
    else
      _ -> nil
    end
  end

  # Registries don't always send `application/json`, so the JSON middleware
  # can leave the body undecoded.
  defp decode(body) when is_map(body), do: body

  defp decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _other -> %{}
    end
  end

  defp decode(_body), do: %{}

  defp client(registry) do
    Tesla.client(
      [{Tesla.Middleware.BaseUrl, registry.base_url}, Tesla.Middleware.JSON],
      adapter()
    )
  end

  defp adapter do
    Application.get_env(:tesla, __MODULE__, [])[:adapter]
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
