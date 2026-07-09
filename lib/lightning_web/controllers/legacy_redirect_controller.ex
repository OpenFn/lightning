defmodule LightningWeb.LegacyRedirectController do
  @moduledoc """
  Redirects retired legacy workflow editor URLs to the collaborative editor.

  The legacy editor (`WorkflowLive.Edit`) has been sunset in favour of the
  collaborative editor (`WorkflowLive.Collaborate`). These actions keep old
  bookmarks working by redirecting `/projects/:project_id/w/.../legacy` URLs to
  their collaborative equivalents.

  The collaborative editor renames the "followed run" param from `a` to `run`,
  so that one is remapped to keep old run bookmarks following the run. Other
  legacy params (e.g. `s`, `m`) depend on the editor's selection state to
  translate correctly, which isn't available here, so they're forwarded as-is.
  """
  use LightningWeb, :controller

  def new(conn, %{"project_id" => project_id}) do
    redirect_preserving_query(conn, "/projects/#{project_id}/w/new")
  end

  def edit(conn, %{"project_id" => project_id, "id" => id}) do
    redirect_preserving_query(conn, "/projects/#{project_id}/w/#{id}")
  end

  defp redirect_preserving_query(conn, base_path) do
    conn = fetch_query_params(conn)

    target =
      case remap_legacy_params(conn.query_params) do
        params when map_size(params) == 0 -> base_path
        params -> base_path <> "?" <> URI.encode_query(params)
      end

    conn
    |> redirect(to: target)
    |> halt()
  end

  defp remap_legacy_params(query_params) do
    case Map.pop(query_params, "a") do
      {nil, params} -> params
      {run, params} -> Map.put(params, "run", run)
    end
  end
end
