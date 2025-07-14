defmodule LightningWeb.LiveComponentPortal do
  @moduledoc """
  Component for rendering content inside layout without full DOM patch.
  Use this when you want to render a LiveComponent outside of the elements parent,
  maybe because of an existing form
  """
  use LightningWeb, :live_component
  alias Phoenix.LiveView.JS

  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.live_component
        :if={@component}
        id={@component.id}
        module={@component.module}
        {@component}
      />
    </div>
    """
  end

  def handle_event("remove_component", _, socket) do
    {:noreply, socket |> assign(component: nil)}
  end

  def update(%{id: id} = assigns, socket) do
    component = assigns[:component]
    {:ok, assign(socket, id: id, component: component)}
  end

  def show_component(module, attrs) do
    send_update(__MODULE__,
      id: "component-portal",
      component: Enum.into(attrs, %{module: module})
    )
  end

  def remove_component do
    send_update(__MODULE__, id: "component-portal", component: nil)
  end

  def remove_component_js(js \\ %JS{}) do
    JS.push(js, "remove_component", target: "#component-portal")
  end
end
