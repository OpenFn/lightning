defmodule Lightning.UpdateCheck.Registry do
  @moduledoc """
  Minimal client for the OCI Distribution API, enough to read an image's
  config, labels and environment included, and to list a repository's tags.
  Works with Docker Hub, GHCR, Harbor and other registries that implement the
  spec.

  Authentication follows the registry's `WWW-Authenticate` challenge. A
  `Bearer` challenge is answered by fetching an anonymous token from its
  realm, which is all public repositories need. Any other challenge fails
  with `:unauthorized`. The resulting `authorization` header is kept on the
  struct, so callers thread the returned struct through later calls and
  authenticate once per check.

  Registries often serve blobs by redirecting to a storage host. Redirects are
  followed, and the `authorization` header is dropped when one leaves the
  registry's origin.
  """

  require Logger

  @manifest_types Enum.join(
                    [
                      "application/vnd.oci.image.index.v1+json",
                      "application/vnd.oci.image.manifest.v1+json",
                      "application/vnd.docker.distribution.manifest.list.v2+json",
                      "application/vnd.docker.distribution.manifest.v2+json"
                    ],
                    ", "
                  )

  @page_size 1000

  defstruct [:base_url, :repository, :authorization]

  @type t :: %__MODULE__{
          base_url: String.t(),
          repository: String.t(),
          authorization: String.t() | nil
        }

  @doc """
  Builds a client from the `:registry` and `:repository` options.
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      base_url: opts |> Keyword.fetch!(:registry) |> String.trim_trailing("/"),
      repository: Keyword.fetch!(opts, :repository)
    }
  end

  @doc """
  Reads the runtime config of the image `tag` points at: the `config` object
  of the image config blob, which holds `Labels` and `Env`. Returns `nil` when
  the tag doesn't exist.

  A multi-platform tag points at an index; the first image in it for a real
  platform is read, skipping attestations. Every platform is built from the
  same source, so their labels match.
  """
  @spec image_config(t(), String.t()) ::
          {:ok, map() | nil, t()} | {:error, term()}
  def image_config(%__MODULE__{} = registry, tag) do
    case fetch_manifest(registry, tag) do
      {:ok, nil, registry} ->
        {:ok, nil, registry}

      {:ok, manifest, registry} ->
        with {:ok, manifest, registry} <- image_manifest(registry, manifest) do
          fetch_config(registry, manifest)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists the repository's tags, in a single request for up to #{@page_size}.
  If the registry says there are more, the tags listed so far are returned and
  a warning is logged, since the tags left out may include the newest
  releases.
  """
  @spec list_tags(t()) :: {:ok, [String.t()], t()} | {:error, term()}
  def list_tags(%__MODULE__{} = registry) do
    case request(registry,
           method: :get,
           url: "/v2/#{registry.repository}/tags/list",
           query: [{"n", to_string(@page_size)}]
         ) do
      {:ok, %Tesla.Env{status: 200, body: body} = env, registry} ->
        if Tesla.get_header(env, "link") do
          Logger.warning(
            "Listed only the first #{@page_size} tags of " <>
              "#{registry.repository}; the update check may miss newer releases"
          )
        end

        {:ok, decode(body)["tags"] || [], registry}

      {:ok, %Tesla.Env{status: status}, _registry} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_manifest(registry, reference) do
    case request(registry,
           method: :get,
           url: "/v2/#{registry.repository}/manifests/#{reference}",
           headers: [{"accept", @manifest_types}]
         ) do
      {:ok, %Tesla.Env{status: 200, body: body}, registry} ->
        {:ok, decode(body), registry}

      {:ok, %Tesla.Env{status: 404}, registry} ->
        {:ok, nil, registry}

      {:ok, %Tesla.Env{status: status}, _registry} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp image_manifest(registry, %{"manifests" => manifests}) do
    case Enum.find(manifests, &image_platform?/1) do
      %{"digest" => digest} -> fetch_manifest(registry, digest)
      nil -> {:error, :no_image_manifest}
    end
  end

  defp image_manifest(registry, manifest), do: {:ok, manifest, registry}

  # Attestations are listed with an `unknown/unknown` platform.
  defp image_platform?(%{"platform" => %{"os" => os}}), do: os != "unknown"
  defp image_platform?(_entry), do: false

  defp fetch_config(registry, %{"config" => %{"digest" => digest}}) do
    case request(registry,
           method: :get,
           url: "/v2/#{registry.repository}/blobs/#{digest}"
         ) do
      {:ok, %Tesla.Env{status: 200, body: body}, registry} ->
        {:ok, decode(body)["config"] || %{}, registry}

      {:ok, %Tesla.Env{status: status}, _registry} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_config(_registry, _manifest), do: {:error, :invalid_manifest}

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
      _other -> {:error, :unauthorized}
    end
  end

  defp fetch_token(registry, %{"realm" => realm} = params) do
    query = params |> Map.take(["service", "scope"]) |> Enum.to_list()

    case Tesla.get(client(registry), realm, query: query) do
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

  @doc false
  # `Bearer realm="https://auth.docker.io/token",service="registry.docker.io"`
  # becomes `{"bearer", %{"realm" => ..., "service" => ...}}`.
  @spec parse_challenge(String.t() | nil) :: {String.t(), map()} | nil
  def parse_challenge(nil), do: nil

  def parse_challenge(header) do
    [scheme | rest] = String.split(String.trim(header), " ", parts: 2)

    params =
      ~r/([A-Za-z_]+)="([^"]*)"/
      |> Regex.scan(Enum.join(rest))
      |> Map.new(fn [_match, key, value] -> {String.downcase(key), value} end)

    {String.downcase(scheme), params}
  end

  # Registries don't always send `application/json`, and manifests and blobs
  # have their own media types, so the JSON middleware can leave the body
  # undecoded.
  defp decode(body) when is_map(body), do: body

  defp decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _other -> %{}
    end
  end

  defp decode(_body), do: %{}

  # FollowRedirects drops `authorization` when a redirect leaves the
  # registry's origin, so the token never reaches a blob storage host.
  defp client(registry) do
    Tesla.client(
      [
        {Tesla.Middleware.BaseUrl, registry.base_url},
        Tesla.Middleware.FollowRedirects,
        Tesla.Middleware.JSON
      ],
      adapter()
    )
  end

  defp adapter do
    Application.get_env(:tesla, __MODULE__, [])[:adapter]
  end
end
