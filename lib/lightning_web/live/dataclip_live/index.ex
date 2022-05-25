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
    case Bodyguard.permit(
           Lightning.Projects.Policy,
           :read,
           socket.assigns.current_user,
           socket.assigns.project
         ) do
      {:error, :unauthorized} ->
        {:ok,
         socket
         |> assign(active_menu_item: nil, project: nil, live_action: :no_access)
         |> put_flash(:nav, :no_access)}

      :ok ->
        {:ok,
         socket
         |> assign(active_menu_item: :dataclips, dataclips: [])}
    end
  end

  def handle_params(_, _url, %{assigns: %{live_action: :no_access}} = socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Dataclip")
    |> assign(:dataclip, Invocation.get_dataclip!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Dataclip")
    |> assign(:dataclip, %Dataclip{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Dataclips")
    |> assign(:dataclips, Invocation.list_dataclips(socket.assigns.project))
    |> assign(:dataclip, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    dataclip = Invocation.get_dataclip!(id)
    {:ok, _} = Invocation.delete_dataclip(dataclip)

    {:noreply,
     assign(
       socket,
       :dataclips,
       Invocation.list_dataclips(socket.assigns.project)
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
