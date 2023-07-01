defmodule LightningWeb.ModalPortal do
  @moduledoc """
  Component for rendering content inside layout without full DOM patch.
  """
  use LightningWeb, :live_component
  alias Phoenix.LiveView.JS

  def render(assigns) do
    ~H"""
    <div id={@id} class={unless @show, do: "hidden"}>
      <.wrapper
        :if={@show}
        title={@show.title}
        id={@show.id}
        class="max-w-full"
        close_modal_target={@myself}
      >
        <.live_component module={@show.module} {@show}>
          <:cancel>
            <Common.button phx-click="close_modal" phx-target={@myself}>
              Cancel
            </Common.button>
          </:cancel>
        </.live_component>
      </.wrapper>
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

  attr :id, :string, default: "modal", doc: "modal id"
  attr :rest, :global
  attr :hide, :boolean, default: false, doc: "modal is hidden"
  attr :title, :string, default: nil, doc: "modal title"

  attr :close_modal_target, :string,
    default: nil,
    doc:
      "close_modal_target allows you to target a specific live component for the close event to go to. eg: close_modal_target={@myself}"

  slot :inner_block, required: true

  defp wrapper(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={!@hide && show_modal(@id)}
      {@rest}
      class="hidden relative z-50"
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
          class={"w-full max-h-full overflow-auto bg-white shadow-lg rounded-xl dark:bg-gray-800 #{@rest[:class]}"}
          role="document"
          phx-click-away={hide_modal(@close_modal_target, @id)}
          phx-window-keydown={hide_modal(@close_modal_target, @id)}
          phx-key="escape"
        >
          <!-- Header -->
          <div class="px-5 py-3 border-b border-gray-100 dark:border-gray-700">
            <div class="flex items-center justify-between">
              <div class="font-semibold text-gray-800 dark:text-gray-200">
                <%= @title %>
              </div>

              <button
                phx-click={hide_modal(@close_modal_target, @id)}
                class="text-gray-400 hover:text-gray-500"
              >
                <div class="sr-only">Close</div>
                <svg class="w-4 h-4 fill-current">
                  <path d="M7.95 6.536l4.242-4.243a1 1 0 111.415 1.414L9.364 7.95l4.243 4.242a1 1 0 11-1.415 1.415L7.95 9.364l-4.243 4.243a1 1 0 01-1.414-1.415L6.536 7.95 2.293 3.707a1 1 0 011.414-1.414L7.95 6.536z" />
                </svg>
              </button>
            </div>
          </div>
          <!-- Content -->
          <div class="p-5">
            <%= render_slot(@inner_block) %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def open_modal(module, attrs) do
    send_update(__MODULE__,
      id: "modal-portal",
      show: Enum.into(attrs, %{module: module})
    )
  end

  def close_modal do
    send_update(__MODULE__, id: "modal-portal", show: nil)
  end

  def hide_modal(close_modal_target \\ nil, id \\ "modal") do
    IO.inspect({close_modal_target, id}, label: "hide_modal")

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

    if close_modal_target do
      JS.push(js, "close_modal", target: close_modal_target)
    else
      JS.push(js, "close_modal")
    end
  end

  # We are unsure of what the best practice is for using this.
  # Open to suggestions/PRs
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
end
