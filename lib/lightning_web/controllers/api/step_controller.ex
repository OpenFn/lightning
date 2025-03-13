defmodule LightningWeb.API.StepController do
  use LightningWeb, :controller

  alias Lightning.Invocation
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects

  @valid_params ~w(page page_size project_id)
  @max_page_size Application.compile_env(
                   :lightning,
                   LightningWeb.API.StepController
                 )[:max_page_size] || 100

  action_fallback LightningWeb.FallbackController

  def index(conn, %{"project_id" => project_id} = params) do
    with :ok <- validate_params(params),
         :ok <- authorize_read(conn, project_id) do
      pagination_attrs =
        params
        |> Map.take(["page", "page_size"])
        |> Map.update(
          "page_size",
          @max_page_size,
          &min(@max_page_size, String.to_integer(&1))
        )

      page =
        project_id
        |> Projects.get_project!()
        |> Invocation.list_steps_for_project(pagination_attrs)

      render(conn, "index.json", %{page: page, conn: conn})
    end
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    with :ok <- authorize_read(conn, project_id) do
      step = Invocation.get_step_with_job!(id)
      render(conn, "show.json", %{step: step, conn: conn})
    end
  end

  defp validate_params(params) do
    with [] <- Map.keys(params) -- @valid_params,
         {_n, ""} <- Integer.parse(params["page"] || "1"),
         {_n, ""} <- Integer.parse(params["page_size"] || "1") do
      :ok
    else
      _invalid -> {:error, :bad_request}
    end
  end

  defp authorize_read(conn, project_id) do
    Permissions.can(
      ProjectUsers,
      :access_project,
      conn.assigns.current_resource,
      %{project_id: project_id}
    )
  end
end
