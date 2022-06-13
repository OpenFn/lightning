defmodule LightningWeb.JobLive.Index do
  @moduledoc """
  LiveView for listing and managing Jobs
  """
  use LightningWeb, :live_view

  alias Lightning.Jobs
  alias Lightning.Jobs.Job
  import LightningWeb.Components.Form

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       active_menu_item: :jobs,
       pagination_path:
         &Routes.project_job_index_path(
           socket,
           :index,
           socket.assigns.project,
           &1
         )
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    socket
    |> assign(
      page_title: "Listing Jobs",
      job: %Job{},
      page: Jobs.jobs_for_project(socket.assigns.project, params)
    )
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    socket
    |> assign(:page_title, "Job")
    |> assign(:job, Jobs.get_job!(id))
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    job = Jobs.get_job!(id)
    {:ok, _} = Jobs.delete_job(job)

    {:noreply,
     socket
     |> assign(page: Jobs.jobs_for_project(socket.assigns.project, %{}))}
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

  def show_job(assigns) do
    ~H"""
    <ul>
      <li>
        <strong>Name:</strong>
        <%= @job.name %>
      </li>

      <li>
        <strong>Body:</strong>
        <%= @job.body %>
      </li>

      <li>
        <strong>Enabled:</strong>
        <%= @job.enabled %>
      </li>
    </ul>

    <span>
      <%= live_redirect("Back",
        to: Routes.project_job_index_path(@socket, :index, @project.id)
      ) %>
    </span>
    |
    <span>
    <%= live_redirect("Edit",
      to: Routes.project_job_edit_path(@socket, :edit, @job.project_id, @job),
      class: "button"
    ) %>
    </span> |
    <span>
    <%= link("Delete",
      to: "#",
      phx_click: "delete",
      phx_value_id: @job.id,
      data: [confirm: "Are you sure?"]
    ) %>
    </span>
    """
  end
end
