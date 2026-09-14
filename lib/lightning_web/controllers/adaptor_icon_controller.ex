defmodule LightningWeb.AdaptorIconURL do
  @moduledoc """
  Builds content-addressable adaptor icon URLs.

  `sha8` is the first 4 raw bytes of the icon's sha256, hex-encoded to 8
  lowercase characters.
  """

  @doc """
  Build a content-addressable icon URL for `name`/`shape`.

  Returns `nil` when `meta` has no ext or sha256 for the requested shape,
  meaning no icon is available.
  """
  alias Lightning.Adaptors.IconField

  @spec build(String.t(), map(), IconField.shape()) :: String.t() | nil
  def build(name, meta, shape) do
    with ext when not is_nil(ext) <- Map.get(meta, IconField.ext(shape)),
         sha when not is_nil(sha) <- Map.get(meta, IconField.sha256(shape)) do
      sha8 = sha |> binary_part(0, 4) |> Base.encode16(case: :lower)

      "/adaptors/icons/#{URI.encode(name, &URI.char_unreserved?/1)}/" <>
        "#{shape}-#{sha8}.#{ext}"
    else
      _ -> nil
    end
  end
end

defmodule LightningWeb.AdaptorIconController do
  @moduledoc """
  Serves content-addressable adaptor icons.

  Route: `/adaptors/icons/:name/:shape-:sha8.:ext`

  `sha8` is defined in `LightningWeb.AdaptorIconURL`. The controller
  compares it against the stored icon metadata and responds with one of:

  - **200** when `sha8` matches. Serves the bytes with a one-year immutable
    cache.
  - **302** when `sha8` is stale but the adaptor still has an icon.
    Redirects to the current-sha URL with `Cache-Control: no-store` on the
    redirect itself.
  - **404** when the adaptor is unknown, the ext mismatches, the shape is
    bad, or there is no icon.
  - **503** with `retry-after` when the catalogue has never loaded.
  """

  use LightningWeb, :controller

  alias Lightning.Adaptors
  alias Lightning.Adaptors.IconField

  @immutable_cache "public, max-age=31536000, immutable"

  # Phoenix path matchers allow one dynamic segment per path component, so
  # the router hands over a single `:filename` of the form
  # `<shape>-<sha8>.<ext>`. The first clause splits it and delegates to the
  # 4-key clause, which stays separate so tests can call it directly.
  @filename_regex ~r/\A(?<shape>[a-z]+)-(?<sha8>[A-Fa-f0-9]+)\.(?<ext>[A-Za-z0-9]+)\z/

  @doc false
  def show(conn, %{"name" => name, "filename" => filename}) do
    case Regex.named_captures(@filename_regex, filename) do
      %{"shape" => shape, "sha8" => sha8, "ext" => ext} ->
        show(conn, %{
          "name" => name,
          "shape" => shape,
          "sha8" => sha8,
          "ext" => ext
        })

      _ ->
        send_resp(conn, 404, "")
    end
  end

  def show(
        conn,
        %{"name" => name, "shape" => shape, "sha8" => sha8, "ext" => ext}
      )
      when shape in ~w(square rectangle) do
    shape = String.to_existing_atom(shape)

    case Adaptors.icon_meta(name) do
      # A catalogue that has never loaded may yet have this icon; anything
      # else is a 404 here rather than a 500.
      {:error, :not_ready} ->
        conn
        |> put_resp_header("retry-after", "5")
        |> send_resp(503, "")

      {:error, _reason} ->
        send_resp(conn, 404, "")

      {:ok, meta} ->
        stored_ext = Map.get(meta, IconField.ext(shape))

        cond do
          is_nil(stored_ext) or stored_ext != ext ->
            send_resp(conn, 404, "")

          sha_matches?(meta, shape, sha8) ->
            serve_bytes(conn, name, shape, ext)

          true ->
            redirect_to_current(conn, name, meta, shape)
        end
    end
  end

  def show(conn, _params), do: send_resp(conn, 404, "")

  defp serve_bytes(conn, name, shape, "png") do
    conn |> put_resp_content_type("image/png") |> send_icon(name, shape)
  end

  defp serve_bytes(conn, name, shape, "svg") do
    conn |> put_resp_content_type("image/svg+xml") |> send_icon(name, shape)
  end

  defp serve_bytes(conn, _name, _shape, _ext), do: send_resp(conn, 404, "")

  # `path` is a cache path built by `Adaptors.icon/2` from a catalogue row,
  # reached only after `icon_meta/1` confirmed the adaptor exists.
  # sobelow_skip ["Traversal.SendFile"]
  defp send_icon(conn, name, shape) do
    case Adaptors.icon(name, shape) do
      {:ok, path} ->
        conn
        |> put_resp_header("cache-control", @immutable_cache)
        |> merge_resp_headers(LightningWeb.Utils.sandboxed_asset_headers())
        |> send_file(200, path)

      {:error, _} ->
        send_resp(conn, 404, "")
    end
  end

  defp redirect_to_current(conn, name, meta, shape) do
    url = LightningWeb.AdaptorIconURL.build(name, meta, shape)

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("location", url)
    |> send_resp(302, "")
  end

  defp sha_matches?(meta, shape, sha8),
    do: sha_prefix_matches?(Map.get(meta, IconField.sha256(shape)), sha8)

  defp sha_prefix_matches?(<<prefix::binary-size(4), _::binary>>, sha8),
    do: Base.encode16(prefix, case: :lower) == String.downcase(sha8)

  defp sha_prefix_matches?(_, _sha8), do: false
end
