defmodule LightningWeb.AdaptorIconURL do
  @moduledoc """
  Single source of truth for content-addressable adaptor-icon URLs.

  Called from `LightningWeb.AdaptorIconController` for redirect targets and —
  in Phase B — from `WorkflowChannel`'s `request_adaptors` payload.

  `sha8` is the first 4 raw bytes of the icon's sha256, hex-encoded
  to 8 lowercase characters, yielding a deterministic content-addressable
  path segment.
  """

  @doc """
  Build a content-addressable icon URL for `name`/`shape`.

  Returns `nil` when the adaptor row has no ext or sha256 for the
  requested shape — i.e. when no icon is available.
  """
  @spec build(String.t(), map(), :square | :rectangle) :: String.t() | nil
  def build(name, meta, shape) do
    with ext when not is_nil(ext) <- Map.get(meta, :"icon_#{shape}_ext"),
         sha when not is_nil(sha) <- Map.get(meta, :"icon_#{shape}_sha256") do
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

  `sha8` is the first 4 raw bytes of the stored sha256 hex-encoded to
  8 lowercase characters. The controller compares `sha8` against the
  DB-projected metadata and responds with one of:

  - **200** — sha matches; serves bytes with a 1-year immutable cache.
  - **302** — sha is stale but the adaptor still has an icon; redirects
    to the canonical (current-sha) URL with `Cache-Control: no-store`
    on the redirect itself.
  - **404** — adaptor unknown, ext mismatch, bad shape, or no icon.
  """

  use LightningWeb, :controller

  alias Lightning.Adaptors.Store

  @immutable_cache "public, max-age=31536000, immutable"

  @doc false
  def show(
        conn,
        %{"name" => name, "shape" => shape, "sha8" => sha8, "ext" => ext}
      )
      when shape in ~w(square rectangle) do
    case Store.icon_meta(Lightning.Adaptors, name) do
      {:error, :not_found} ->
        send_resp(conn, 404, "")

      {:ok, meta} ->
        cond do
          ext_for_shape(meta, shape) != ext ->
            send_resp(conn, 404, "")

          not has_icon?(meta, shape) ->
            send_resp(conn, 404, "")

          sha_matches?(meta, shape, sha8) ->
            serve_bytes(conn, name, shape, ext)

          true ->
            redirect_to_current(conn, name, meta, shape)
        end
    end
  end

  def show(conn, _params), do: send_resp(conn, 404, "")

  defp serve_bytes(conn, name, shape, ext) do
    case Store.icon(Lightning.Adaptors, name, String.to_existing_atom(shape)) do
      {:ok, path} ->
        conn
        |> put_resp_content_type(content_type_for(ext))
        |> put_resp_header("cache-control", @immutable_cache)
        |> send_file(200, path)

      {:error, _} ->
        send_resp(conn, 404, "")
    end
  end

  defp redirect_to_current(conn, name, meta, shape) do
    url =
      LightningWeb.AdaptorIconURL.build(
        name,
        meta,
        String.to_existing_atom(shape)
      )

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("location", url)
    |> send_resp(302, "")
  end

  defp has_icon?(meta, shape), do: not is_nil(ext_for_shape(meta, shape))

  defp ext_for_shape(meta, shape), do: Map.get(meta, :"icon_#{shape}_ext")

  defp sha_matches?(meta, shape, sha8) do
    case Map.get(meta, :"icon_#{shape}_sha256") do
      <<prefix::binary-size(4), _::binary>> ->
        Base.encode16(prefix, case: :lower) == String.downcase(sha8)

      _ ->
        false
    end
  end

  defp content_type_for("png"), do: "image/png"
  defp content_type_for("svg"), do: "image/svg+xml"
end
