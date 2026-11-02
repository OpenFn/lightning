defmodule LightningWeb.API.HistoryExportJSON do
  @moduledoc false

  import LightningWeb.API.Helpers

  alias LightningWeb.Router.Helpers, as: Routes

  def render("index.json", %{page: page, conn: conn}) do
    %{
      data: Enum.map(page.entries, &resource(conn, &1)),
      included: [],
      links: pagination_links(conn, page, %{})
    }
  end

  def render("show.json", %{export: export, conn: conn}) do
    %{
      data: resource(conn, export),
      included: [],
      links: %{self: url(conn, export)}
    }
  end

  defp resource(conn, export) do
    completed? = export.status == :completed

    %{
      type: "history_exports",
      id: export.id,
      attributes: %{
        state: export.status,
        filename: if(completed?, do: Path.basename(export.path)),
        created_by_id: export.created_by_id,
        created_by_name: name(export.created_by),
        download_url:
          if(completed?,
            do:
              Routes.api_history_export_url(
                conn,
                :download,
                export.project_id,
                export.id
              )
          ),
        inserted_at: export.inserted_at,
        updated_at: export.updated_at
      },
      relationships: %{},
      links: %{self: url(conn, export)}
    }
  end

  defp url(conn, export),
    do: Routes.api_history_export_url(conn, :show, export.project_id, export.id)

  defp name(%{first_name: first, last_name: last}),
    do: [first, last] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" ")

  defp name(_no_user), do: nil
end
