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
      phx-mounted={!@hide && on_show(@id)}
      {@rest}
      class="hidden relative z-50"
    >
      <div
        class="fixed inset-0 z-50 transition-opacity bg-gray-50/90 dark:bg-gray-900/90"
        aria-hidden="true"
      >
      </div>

      <div
        class="fixed inset-0 z-50 justify-center items-center flex px-4 my-4 transform sm:px-6"
        role="dialog"
        aria-modal="true"
      >
        <div
          class={"flex flex-col isolate bg-white shadow-lg rounded-xl md:min-w-[50%] min-w-full dark:bg-gray-800 #{@rest[:class]}"}
          role="document"
          phx-click-away={on_hide(@close_modal_target, @id)}
          phx-window-keydown={on_hide(@close_modal_target, @id)}
          phx-key="escape"
        >
          <!-- Header -->
          <div class="flex-none px-5 py-3 border-b border-gray-100 dark:border-gray-700">
            <div class="flex items-center justify-between">
              <div class="font-semibold text-gray-800 dark:text-gray-200">
                <%= @title %>
              </div>

              <button
                phx-click={on_hide(@close_modal_target, @id)}
                class="text-gray-400 hover:text-gray-500"
              >
                <div class="sr-only">Close</div>
                <Heroicons.x_mark class="w-4 h-4" />
              </button>
            </div>
          </div>
          <!-- Content -->
          <div class="grow w-full p-5 overflow-y-auto">
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

  def on_hide(close_modal_target \\ nil, id \\ "modal") do
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
  def on_show(js \\ %JS{}, id) do
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
