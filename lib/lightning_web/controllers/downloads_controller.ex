defmodule LightningWeb.DownloadsController do
  use LightningWeb, :controller

  alias Lightning.Projects

  def download_project_yaml(conn, %{"id" => id}) do
    {:ok, yaml} = Projects.export_project(:yaml, id)

    conn
    |> put_resp_content_type("text/yaml")
    |> put_resp_header(
      "content-disposition",
      "attachment; filename=\"project-#{id}.yaml\""
    )
    |> put_root_layout(false)
    |> put_flash(:info, "Project yaml exported successfully")
    |> send_resp(200, yaml)
  end
end
