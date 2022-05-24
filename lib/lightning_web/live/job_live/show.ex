defmodule LightningWeb.JobLive.Show do
  @moduledoc """
  LiveView for viewing a single Job
  """
  use LightningWeb, :live_view

  alias Lightning.Jobs

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:active_menu_item, :jobs)
     |> assign_or_not_found(:job, Jobs.get_job(id))}
  end

  defp page_title(:show), do: "Show Job"
  defp page_title(:edit), do: "Edit Job"

  def assign_or_not_found(socket, key, val) do
    if is_nil(val) do
      socket |> put_flash(:nav, :not_found)
    else
      socket |> assign(key, val)
    end
  end
end
