defmodule LightningWeb.Components.Modal do
  @moduledoc """
  A modal component that can be used to display a modal on the page.

  This currently isn't used anywhere but should be used in the future to
  replace the existing modal implementations.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :type, :string, default: "default"
  attr :position, :string, default: "relative"
  attr :width, :string, default: "max-w-3xl"

  attr :on_close, JS, default: JS.push(%JS{}, "modal_closed")
  attr :on_open, JS, default: %JS{}

  slot :inner_block, required: true
  slot :title
  slot :subtitle

  def modal(%{type: "default"} = assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      class={"#{@position} z-50 hidden"}
    >
      <div
        id={"#{@id}-bg"}
        class="fixed inset-0 bg-black bg-opacity-60 transition-opacity"
        aria-hidden="true"
      />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class={"#{@width} p-4 sm:p-6 lg:py-8"}>
            <.focus_wrap
              id={"#{@id}-container"}
              phx-mounted={@show && show_modal(@on_open, @id)}
              phx-window-keydown={hide_modal(@on_close, @id)}
              phx-key="escape"
              phx-click-away={hide_modal(@on_close, @id)}
              class="hidden relative rounded-xl bg-white p-6 shadow-lg shadow-zinc-700/10 ring-1 ring-zinc-700/10 transition"
            >
              <div id={"#{@id}-content"}>
                <header :if={@title != []}>
                  <h1
                    id={"#{@id}-title"}
                    class="text-lg font-semibold leading-8 text-zinc-800"
                  >
                    <%= render_slot(@title) %>
                  </h1>
                  <p
                    :if={@subtitle != []}
                    class="mt-2 text-sm leading-6 text-zinc-600"
                  >
                    <%= render_slot(@subtitle) %>
                  </p>
                </header>
                <%= render_slot(@inner_block) %>
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # def modal(assigns) do
  #   ~H"""
  #   <div
  #     id={@id}
  #     phx-update={@show && show_modal(@id)}
  #     phx-mounted={@show && show_modal(@id)}
  #     phx-remove={hide_modal(@id, @close_event, @close_target)}
  #     class="relative z-50"
  #     style="display: none;"
  #   >
  #     <div
  #       class="fixed inset-0 z-50 transition-opacity bg-gray-50/90 dark:bg-gray-900/90"
  #       aria-hidden="true"
  #     >
  #     </div>
  #     <div
  #       class="fixed inset-0 z-50 flex items-center justify-center px-4 my-4 overflow-hidden transform sm:px-6"
  #       role="dialog"
  #       aria-modal="true"
  #     >
  #       <div
  #         class="w-full max-h-full overflow-auto bg-white opacity-1 shadow-lg rounded-xl dark:bg-gray-800"
  #         role="document"
  #         phx-remove={hide_modal(@id, @close_event, @close_target)}
  #         phx-window-keydown={hide_modal(@id, @close_event, @close_target)}
  #         phx-key="escape"
  #       >
  #         <%= render_slot(@inner_block, hide_modal(@id, @close_event, @close_target)) %>
  #       </div>
  #     </div>
  #   </div>
  #   """
  # end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition:
        {"transition-all transform ease-out duration-300", "opacity-0",
         "opacity-100"}
    )
    |> JS.show(
      to: "##{id}-container",
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition:
        {"transition-all transform ease-in duration-200", "opacity-100",
         "opacity-0"}
    )
    |> JS.hide(
      to: "##{id}-container",
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.pop_focus()
  end
end
