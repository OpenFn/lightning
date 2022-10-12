defmodule LightningWeb.JobLive.Edit do
  @moduledoc """
  LiveView for editing a single job, which inturn uses `LightningWeb.JobLive.JobFormComponent`
  for common functionality.
  """
  use LightningWeb, :live_view

  alias Lightning.Jobs
  alias Lightning.Jobs.Job
  alias Lightning.Projects

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
     )
     |> assign(:initial_job_params, %{})
     |> assign(:new_credential, false)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("new-credential", params, socket) do
    {:noreply,
     socket
     |> assign(:new_credential, true)
     |> assign(:initial_job_params, params)}
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, socket |> assign(:new_credential, false)}
  end

  @impl true
  def handle_info({:added_credential, credential}, socket) do
    project = socket.assigns.project

    project_credential =
      Projects.get_project_credential(project.id, credential.id)

    {:noreply,
     socket
     |> put_flash(:info, "Credential created successfully")
     |> assign(
       initial_job_params:
         Map.merge(socket.assigns.initial_job_params, %{
           "project_credential_id" => project_credential.id,
           "project_credential" => project_credential
         })
     )
     |> assign(:new_credential, false)}
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
    |> assign(:initial_job_params, %{
      "project_id" => socket.assigns.project.id
    })
  end
end
