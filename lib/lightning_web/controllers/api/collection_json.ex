defmodule LightningWeb.API.CollectionJSON do
  @moduledoc """
  JSON views for the pages of collections. Each collection carries
  `byte_size_sum`, the bytes its keys and values take up, and on the page of
  every project's collections, `project_name`.
  """

  import LightningWeb.API.Helpers

  @fields [:id, :project_id, :name, :byte_size_sum]

  def index(%{page: page, filters: filters, conn: conn}) do
    %{
      data: Enum.map(page.entries, &Map.take(&1, @fields)),
      links: pagination_links(conn, page, filters)
    }
  end

  def index_all(%{page: page, filters: filters, conn: conn}) do
    %{
      data:
        Enum.map(
          page.entries,
          &(&1 |> Map.take(@fields) |> Map.put(:project_name, &1.project.name))
        ),
      links: pagination_links(conn, page, filters)
    }
  end
end
