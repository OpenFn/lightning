defmodule LightningWeb.LegacyRedirectController do
  @moduledoc """
  Redirects retired legacy workflow editor URLs to the collaborative editor.

  The legacy editor (`WorkflowLive.Edit`) has been sunset in favour of the
  collaborative editor (`WorkflowLive.Collaborate`). These actions keep old
  bookmarks working by redirecting `/projects/:project_id/w/.../legacy` URLs to
  their collaborative equivalents, preserving the original query string.

  The collaborative editor uses different query param names than the legacy
  editor, so the raw query string is forwarded as-is rather than mapped.
  """
  use LightningWeb, :controller

  def new(conn, %{"project_id" => project_id}) do
    redirect_preserving_query(conn, "/projects/#{project_id}/w/new")
  end

  def edit(conn, %{"project_id" => project_id, "id" => id}) do
    redirect_preserving_query(conn, "/projects/#{project_id}/w/#{id}")
  end

  defp redirect_preserving_query(conn, base_path) do
    target =
      case conn.query_string do
        "" -> base_path
        query -> base_path <> "?" <> query
      end

    conn
    |> redirect(to: target)
    |> halt()
  end
end
