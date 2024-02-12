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
  attr :rest, :global

  attr :on_close, JS, default: %JS{}
  attr :on_open, JS, default: %JS{}

  slot :inner_block, required: true
  slot :title
  slot :subtitle

  slot :footer do
    attr :class, :string
  end

  def modal(%{type: "default"} = assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-on-close={hide_modal(@id)}
      phx-hook="ModalHook"
      class={"#{@position} z-50 hidden"}
      {@rest}
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
        <div class="flex flex-col min-h-full items-center justify-center">
          <div class={@width}>
            <.focus_wrap
              id={"#{@id}-container"}
              phx-mounted={@show && show_modal(@on_open, @id)}
              phx-window-keydown={hide_modal(@on_close, @id)}
              phx-key="escape"
              phx-click-away={hide_modal(@on_close, @id)}
              class="hidden relative rounded-xl bg-white py-[24px] shadow-lg shadow-zinc-700/10 ring-1 ring-zinc-700/10 transition"
            >
              <header :if={@title != []} class="pl-[24px] pr-[24px]">
                <h1
                  id={"#{@id}-title"}
                  class="text-lg font-semibold leading-5 text-zinc-800"
                >
                  <%= render_slot(@title) %>
                </h1>
                <%= for subtitle <- @subtitle do %>
                  <p class="mt-2 text-sm leading-4.5 text-zinc-600">
                    <%= render_slot(subtitle) %>
                  </p>
                <% end %>
              </header>
              <div class="flex-grow bg-gray-100 h-0.5 my-[16px]"></div>
              <section class="pl-[0px] pr-[0px]">
                <%= render_slot(@inner_block) %>
              </section>
              <%= for footer <- @footer do %>
                <.modal_footer class={footer |> Map.get(:class)}>
                  <%= render_slot(footer) %>
                </.modal_footer>
              <% end %>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :class, :any, default: ""
  slot :inner_block, required: true

  def modal_footer(assigns) do
    ~H"""
    <div class="flex-grow bg-gray-100 h-0.5 mt-[16px]"></div>
    <footer class={@class}>
      <%= render_slot(@inner_block) %>
    </footer>
    """
  end

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
