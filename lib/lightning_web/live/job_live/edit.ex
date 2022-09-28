defmodule LightningWeb.JobLive.Edit do
  @moduledoc """
  LiveView for editing a single job, which inturn uses `LightningWeb.JobLive.JobFormComponent`
  for common functionality.
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
       active_menu_item: :jobs,
       pagination_path:
         &Routes.project_job_edit_path(
           socket,
           :edit,
           socket.assigns.project,
           &1
         )
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
    |> assign(:initial_params, %{
      "project_id" => socket.assigns.project.id
    })
  end
end
