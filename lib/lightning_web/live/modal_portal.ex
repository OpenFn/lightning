defmodule LightningWeb.ModalPortal do
  @moduledoc """
  Component for rendering content inside layout without full DOM patch.
  """
  use LightningWeb, :live_component

  def show_modal(module, attrs) do
    send_update(__MODULE__,
      id: "modal-portal",
      show: Enum.into(attrs, %{module: module})
    )
  end

  def close_modal do
    send_update(__MODULE__, id: "modal-portal", show: nil)
  end

  def render(assigns) do
    ~H"""
    <div class={unless @show, do: "hidden"}>
      <%= if @show do %>
        <PetalComponents.Modal.modal
          max_width="lg"
          title={@show.title}
          close_modal_target={@myself}
        >
          <.live_component module={@show.module} {@show}>
            <:cancel>
              <Common.button phx-click="close_modal" phx-target={@myself}>
                Cancel
              </Common.button>
            </:cancel>
          </.live_component>
        </PetalComponents.Modal.modal>
      <% end %>
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
end
