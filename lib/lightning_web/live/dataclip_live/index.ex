defmodule LightningWeb.DataclipLive.Index do
  @moduledoc """
  LiveView for listing and working with a list of Dataclips
  """
  use LightningWeb, :live_view

  alias Lightning.Invocation
  alias Lightning.Invocation.Dataclip

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       active_menu_item: :dataclips,
       pagination_path:
         &Routes.project_dataclip_index_path(
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
      page_title: "Dataclips",
      dataclip: %Dataclip{},
      page:
        Invocation.list_dataclips_query(socket.assigns.project)
        |> Lightning.Repo.paginate(params)
    )
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    dataclip = Invocation.get_dataclip!(id)
    {:ok, _} = Invocation.delete_dataclip(dataclip)

    {:noreply,
     socket
     |> assign(
       page:
         Invocation.list_dataclips_query(socket.assigns.project)
         |> Lightning.Repo.paginate(%{})
     )}
  end
end
