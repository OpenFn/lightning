defmodule LightningWeb.API.Helpers do
  @moduledoc """
  Helpers for the API views
  """
  alias LightningWeb.Router.Helpers, as: Routes

  def pagination_links(conn, page) do
    %{
      first: pagination_link(conn, page, :first),
      last: pagination_link(conn, page, :last),
      next: pagination_link(conn, page, :next),
      prev: pagination_link(conn, page, :prev)
    }
  end

  def pagination_link(conn, _page, :first) do
    url_for(conn, conn.query_params |> Map.put("page", 1))
  end

  def pagination_link(conn, page, :last) do
    url_for(conn, conn.query_params |> Map.put("page", page.total_pages))
  end

  def pagination_link(conn, page, :next) do
    if page.page_number < page.total_pages do
      url_for(
        conn,
        conn.query_params
        |> Map.put("page", page.page_number + 1)
      )
    end
  end

  def pagination_link(conn, page, :prev) do
    if page.page_number > 1 do
      url_for(
        conn,
        conn.query_params
        |> Map.put(
          "page",
          page.page_number - 1
        )
      )
    end
  end

  def url_for(conn, params \\ %{}) do
    %URI{
      URI.new!(Routes.url(conn) <> conn.request_path)
      | query: conn.query_params |> Map.merge(params) |> Plug.Conn.Query.encode()
    }
    |> URI.to_string()
  end

  @doc """
  Validates that the given value is a well-formed UUID.

  Returns `:ok` on success or `{:error, :bad_request}` when the value
  cannot be parsed as a UUID. Use this in API controllers before passing
  an ID to the database layer, which would raise `Ecto.Query.CastError`
  for invalid values.
  """
  @spec validate_uuid(any()) :: :ok | {:error, :bad_request}
  def validate_uuid(id) do
    case Ecto.UUID.dump(to_string(id)) do
      {:ok, _bin} -> :ok
      :error -> {:error, :bad_request}
    end
  end
end
