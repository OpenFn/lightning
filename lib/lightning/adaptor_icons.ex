defmodule Lightning.AdaptorIcons do
  @moduledoc """
  Manages adaptor icon data in the DB-backed cache.

  Builds a manifest from the adaptor registry and optionally prefetches
  icon PNGs from GitHub into the cache so they are served instantly by
  `LightningWeb.AdaptorIconController`.
  """

  require Logger

  @github_base "https://raw.githubusercontent.com/OpenFn/adaptors/main/packages"
  @shapes ["square", "rectangle"]

  @doc """
  Refreshes the icon manifest and spawns a background task to prefetch
  all icons from GitHub.

  Returns `{:ok, manifest}` immediately after the manifest is stored.
  """
  @spec refresh() :: {:ok, map()} | {:error, term()}
  def refresh do
    case refresh_manifest() do
      {:ok, manifest} ->
        Task.start(fn -> prefetch_icons(manifest) end)
        {:ok, manifest}

      error ->
        error
    end
  end

  @doc """
  Builds the icon manifest from the adaptor registry and stores it in
  the DB cache. Broadcasts cache invalidation so all nodes pick up the
  new manifest.

  Returns `{:ok, manifest}` where manifest is the JSON-decoded map.
  """
  @spec refresh_manifest() :: {:ok, map()} | {:error, term()}
  def refresh_manifest do
    adaptors = Lightning.AdaptorRegistry.all()

    manifest =
      adaptors
      |> Enum.map(fn %{name: name} ->
        short = short_name(name)

        sources =
          Map.new(@shapes, fn shape ->
            {shape, "/images/adaptors/#{short}-#{shape}.png"}
          end)

        {short, sources}
      end)
      |> Enum.into(%{})

    json_data = Jason.encode!(manifest)

    case Lightning.AdaptorData.put(
           "icon_manifest",
           "all",
           json_data,
           "application/json"
         ) do
      {:ok, _entry} ->
        Lightning.AdaptorData.Cache.broadcast_invalidation([
          "icon_manifest"
        ])

        {:ok, manifest}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Prefetches icon PNGs for all adaptors and shapes. Skips icons that
  are already cached in the DB.
  """
  @spec prefetch_icons(map()) :: :ok
  def prefetch_icons(manifest) do
    client = Tesla.client([Tesla.Middleware.FollowRedirects])

    manifest
    |> Enum.each(fn {adaptor, _sources} ->
      Enum.each(@shapes, fn shape ->
        cache_key = "#{adaptor}-#{shape}"

        case Lightning.AdaptorData.get("icon", cache_key) do
          {:ok, _entry} ->
            :ok

          {:error, :not_found} ->
            fetch_and_store_icon(client, adaptor, shape, cache_key)
        end
      end)
    end)

    Lightning.AdaptorData.Cache.broadcast_invalidation(["icon"])
    :ok
  end

  defp fetch_and_store_icon(client, adaptor, shape, cache_key) do
    url = "#{@github_base}/#{adaptor}/assets/#{shape}.png"

    case Tesla.get(client, url) do
      {:ok, %{status: 200, body: body}} ->
        Lightning.AdaptorData.put("icon", cache_key, body, "image/png")
        :ok

      {:ok, %{status: status}} ->
        Logger.debug("Icon not found for #{adaptor}/#{shape} (HTTP #{status})")

        :skip

      {:error, reason} ->
        Logger.warning(
          "Failed to fetch icon #{adaptor}/#{shape}: " <>
            "#{inspect(reason)}"
        )

        :error
    end
  end

  defp short_name("@openfn/language-" <> rest), do: rest
  defp short_name(name), do: name
end
