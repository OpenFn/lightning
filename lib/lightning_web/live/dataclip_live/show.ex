defmodule LightningWeb.DataclipLive.Show do
  @moduledoc """
  LiveView for showing a single dataclip.
  """
  use LightningWeb, :live_view

  alias Lightning.Invocation

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(active_menu_item: :dataclip)}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    {:noreply,
     socket
     |> assign(:id, id)
     |> assign(:page_title, "Dataclip #{String.slice(id, 0..7)}")
     |> assign(:dataclip, Invocation.get_dataclip_details!(id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:title><%= @page_title %></:title>
        </LayoutComponents.header>
      </:header>
      <LayoutComponents.centered>
        <.live_component
          module={LightningWeb.DataclipLive.FormComponent}
          id={@id}
          action={@live_action}
          dataclip={@dataclip}
          project={@project}
        />
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    """
  end
end
