defmodule LightningWeb.Components.Modal do
  use LightningWeb, :component

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :close_event, :string, default: "modal_closed"
  attr :close_target, :any, default: nil
  attr :show, :boolean, default: false
  attr :on_change, :any
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-update={@show && show_modal(@id)}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id, @close_event, @close_target)}
      class="relative z-50"
      style="display: none;"
    >
      <div
        class="fixed inset-0 z-50 transition-opacity bg-gray-50/90 dark:bg-gray-900/90"
        aria-hidden="true"
      >
      </div>
      <div
        class="fixed inset-0 z-50 flex items-center justify-center px-4 my-4 overflow-hidden transform sm:px-6"
        role="dialog"
        aria-modal="true"
      >
        <div
          class="w-full max-h-full overflow-auto bg-white opacity-1 shadow-lg rounded-xl dark:bg-gray-800"
          role="document"
          phx-remove={hide_modal(@id, @close_event, @close_target)}
          phx-window-keydown={hide_modal(@id, @close_event, @close_target)}
          phx-key="escape"
        >
          <%= render_slot(@inner_block, hide_modal(@id, @close_event, @close_target)) %>
        </div>
      </div>
    </div>
    """
  end

  def show_modal(js \\ %JS{}, id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id} [aria-hidden]",
      transition:
        {"transition-all transform ease-out duration-300", "opacity-0",
         "opacity-100"}
    )
    |> JS.show(
      to: "##{id} [role='document']",
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id} [role='document']")
  end

  def hide_modal(id, close_event, event_target) do
    js =
      %JS{}
      |> JS.hide(
        to: "##{id} [aria-hidden]",
        transition:
          {"transition-all transform ease-in duration-200", "opacity-100",
           "opacity-0"}
      )
      |> JS.hide(
        to: "##{id} [role='document']",
        time: 200,
        transition:
          {"transition-all transform ease-in duration-200",
           "opacity-100 translate-y-0 sm:scale-100",
           "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
      )
      |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
      |> JS.remove_class("overflow-hidden", to: "body")

    if event_target do
      JS.push(js, close_event, target: event_target)
    else
      JS.push(js, close_event)
    end
  end
end
