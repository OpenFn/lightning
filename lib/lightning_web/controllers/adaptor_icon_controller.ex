defmodule LightningWeb.AdaptorIconController do
  @moduledoc """
  Serves adaptor icons and the icon manifest from the DB/Cachex cache.

  On cache miss, delegates to `Lightning.AdaptorIcons.fetch_icon_bytes/2`,
  which reads from the local adaptors repo when `LOCAL_ADAPTORS` mode is
  on and otherwise fetches from `raw.githubusercontent.com/OpenFn/adaptors`.
  """
  use LightningWeb, :controller

  require Logger

  @icon_max_age 604_800
  @manifest_max_age 300

  @doc """
  Serves an individual adaptor icon PNG.

  The filename is expected in the format `{adaptor}-{shape}.png` where
  shape is "square" or "rectangle". The adaptor name may itself contain
  hyphens (e.g., "google-sheets-square.png").
  """
  def show(conn, %{"icon" => filename}) do
    case parse_icon_filename(filename) do
      {:ok, adaptor, shape} ->
        cache_key = "#{adaptor}-#{shape}"

        case Lightning.AdaptorData.Cache.get("icon", cache_key) do
          %{data: data, content_type: content_type} ->
            serve_icon(conn, data, content_type)

          nil ->
            fetch_and_serve_icon(conn, adaptor, shape, cache_key)
        end

      :error ->
        send_resp(conn, 400, "Invalid icon filename")
    end
  end

  @doc """
  Serves the adaptor icon manifest JSON.
  """
  def manifest(conn, _params) do
    data =
      case Lightning.AdaptorData.Cache.get("icon_manifest", "all") do
        %{data: data} -> data
        nil -> "{}"
      end

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", "public, max-age=#{@manifest_max_age}")
    |> send_resp(200, data)
  end

  defp parse_icon_filename(filename) do
    basename = Path.rootname(filename)
    parts = String.split(basename, "-")

    case Enum.reverse(parts) do
      [shape | rest] when shape in ["square", "rectangle"] and rest != [] ->
        adaptor = rest |> Enum.reverse() |> Enum.join("-")
        {:ok, adaptor, shape}

      _ ->
        :error
    end
  end

  defp serve_icon(conn, data, content_type) do
    conn
    |> put_resp_content_type(content_type)
    |> put_resp_header(
      "cache-control",
      "public, max-age=#{@icon_max_age}"
    )
    |> send_resp(200, data)
  end

  defp fetch_and_serve_icon(conn, adaptor, shape, cache_key) do
    case Lightning.AdaptorIcons.fetch_icon_bytes(adaptor, shape) do
      {:ok, body} ->
        Lightning.AdaptorData.put(
          "icon",
          cache_key,
          body,
          "image/png"
        )

        Lightning.AdaptorData.Cache.put(
          "icon",
          cache_key,
          %{data: body, content_type: "image/png"}
        )

        serve_icon(conn, body, "image/png")

      {:error, {:http, 404}} ->
        send_resp(conn, 404, "Not Found")

      {:error, {:http, status}} ->
        Logger.warning(
          "Upstream returned #{status} fetching icon for #{adaptor}/#{shape}"
        )

        send_resp(conn, 502, "Bad Gateway")

      {:error, reason} ->
        Logger.warning(
          "Failed to fetch icon for #{adaptor}/#{shape}: " <>
            "#{inspect(reason)}"
        )

        send_resp(conn, 502, "Bad Gateway")
    end
  end
end
