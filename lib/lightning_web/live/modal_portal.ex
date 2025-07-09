defmodule LightningWeb.ModalPortal do
  @moduledoc """
  Component for rendering content inside layout without full DOM patch.
  """
  use LightningWeb, :live_component
  alias Phoenix.LiveView.JS

  @modal_id "modal-portal"

  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.live_component :if={@show} id={@show.id} module={@show.module} {@show} />
    </div>
    """
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, socket |> assign(show: nil)}
  end

  def update(%{id: id} = assigns, socket) do
    show = assigns[:show]
    {:ok, assign(socket, id: id, show: show)}
  end

  def open_modal(module, attrs) do
    send_update(__MODULE__,
      id: @modal_id,
      show: Enum.into(attrs, %{module: module})
    )
  end

  def close_modal do
    send_update(__MODULE__, id: @modal_id, show: nil)
  end

  def close_modal_js(js \\ %JS{}) do
    JS.push(js, "close_modal", target: "##{@modal_id}")
  end
end
