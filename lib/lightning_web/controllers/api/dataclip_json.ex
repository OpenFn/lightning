defmodule LightningWeb.API.DataclipJSON do
  @moduledoc false

  import LightningWeb.API.Helpers

  alias LightningWeb.Router.Helpers, as: Routes

  @fields ~w(name type project_id wiped_at inserted_at updated_at)a

  def render("show.json", %{dataclip: dataclip, body: body, conn: conn}) do
    %{
      data: %{
        type: "dataclips",
        id: dataclip.id,
        attributes: dataclip |> Map.take(@fields) |> Map.put(:body, body),
        relationships: %{},
        links: %{self: Routes.api_dataclip_url(conn, :show, dataclip)}
      },
      included: [],
      links: %{self: self_url(conn)}
    }
  end
end
