defmodule LightningWeb.API.WorkflowVersionJSON do
  @moduledoc """
  JSON views for a workflow's versions.
  """
  import LightningWeb.API.Helpers

  def index(%{page: page, conn: conn}) do
    %{
      data:
        Enum.map(page.entries, fn version ->
          %{
            hash: version.hash,
            source: version.source,
            inserted_at: version.inserted_at
          }
        end),
      links: pagination_links(conn, page, %{})
    }
  end
end
