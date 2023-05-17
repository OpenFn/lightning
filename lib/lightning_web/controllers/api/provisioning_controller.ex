defmodule LightningWeb.API.ProvisioningController do
  use LightningWeb, :controller

  alias Lightning.Projects
  alias Lightning.Projects.{Provisioner, Project}

  action_fallback LightningWeb.FallbackController

  def create(conn, params) do
    with project <- get_or_build_project(params),
         {:ok, project} <- Provisioner.import_document(project, params) do
      # TODO: check if the user is allowed to update this project
      # TODO: check if the user is allowed to provision a project

      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/provision/#{project.id}")
      |> render("create.json", project: project)
    end
  end

  def show(conn, params) do
    with project <-
           Provisioner.load_project(params["id"]) || {:error, :not_found} do
      # TODO: check if the user is allowed to update this project
      # TODO: check if the user is allowed to provision a project

      conn
      |> put_status(:ok)
      |> render("create.json", project: project)
    end
  end

  defp get_or_build_project(params) do
    params
    |> case do
      %{"id" => id} -> Projects.get_project(id) || %Project{}
      _ -> %Project{}
    end
  end
end
