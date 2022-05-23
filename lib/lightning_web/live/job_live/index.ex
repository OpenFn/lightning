defmodule LightningWeb.JobLive.Index do
  @moduledoc """
  LiveView for listing and managing Jobs
  """
  use LightningWeb, :live_view

  alias Lightning.Jobs
  alias Lightning.Jobs.Job

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       jobs: Jobs.jobs_for_project(socket.assigns.project),
       active_menu_item: :jobs
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Job")
    |> assign(:job, Jobs.get_job!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Job")
    |> assign(
      :adaptors,
      Lightning.AdaptorRegistry.all() |> Enum.map(fn %{name: name} -> name end)
    )
    |> assign(
      :credentials,
      Lightning.Credentials.list_credentials()
    )
    |> assign(:job, %Job{project_id: socket.assigns.project.id})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Jobs")
    |> assign(:job, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    job = Jobs.get_job!(id)
    {:ok, _} = Jobs.delete_job(job)

    {:noreply, assign(socket, :jobs, list_jobs())}
  end

  defp list_jobs do
    Jobs.list_jobs()
  end
end
