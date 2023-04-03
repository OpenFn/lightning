defmodule LightningWeb.API.ProvisioningController do
  use LightningWeb, :controller

  alias Lightning.Projects

  action_fallback LightningWeb.FallbackController

  def create(conn, params) do
    Projects.import_project(params, conn.assigns.current_user)

    render(conn, "create.json", conn: conn)
  end
end

defmodule LightningWeb.API.ProvisioningJSON do
  @moduledoc false
  # import LightningWeb.API.Helpers

  def render("create.json", %{conn: _conn}) do
    %{}
  end
end
