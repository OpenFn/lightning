defmodule LightningWeb.JobLive.Index do
  @moduledoc """
  LiveView for listing and managing Jobs
  """
  use LightningWeb, :live_view

  alias Lightning.Jobs
  alias Lightning.Jobs.Job
  import LightningWeb.Components.Form
  import LightningWeb.Components.Common

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    case Bodyguard.permit(
           Lightning.Projects.Policy,
           :index,
           socket.assigns.current_user,
           socket.assigns.project
         ) do
      :ok ->
        {:ok,
         socket
         |> assign(
           active_menu_item: :overview,
           pagination_path:
             &Routes.project_job_index_path(
               socket,
               :index,
               socket.assigns.project,
               &1
             )
         )}

      {:error, :unauthorized} ->
        {:ok,
         put_flash(socket, :error, "You can't access that page")
         |> push_redirect(to: "/")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    socket
    |> assign(
      page_title: "Jobs",
      job: %Job{},
      page:
        Jobs.jobs_for_project_query(socket.assigns.project)
        |> Lightning.Repo.paginate(params)
    )
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    job = Jobs.get_job!(id)
    {:ok, _} = Jobs.delete_job(job)

    {:noreply,
     socket
     |> assign(
       page:
         Jobs.jobs_for_project_query(socket.assigns.project)
         |> Lightning.Repo.paginate(%{})
     )}
  end
end
