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

  def type_pill(assigns) do
    base_classes = ~w[
      px-2 py-1 rounded-full inline-block text-sm font-mono
    ]

    class =
      base_classes ++
        case assigns[:dataclip].type do
          :run_result -> ~w[bg-purple-500 text-purple-900]
          :http_request -> ~w[bg-green-500 text-green-900]
          _ -> []
        end

    assigns = assign(assigns, class: class)

    ~H"""
    <div class={@class}>
      <%= @dataclip.type %>
    </div>
    """
  end
end
