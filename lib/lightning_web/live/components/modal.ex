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
  attr :position, :string, default: "fixed inset-0"
  attr :width, :string, default: "max-w-3xl"
  attr :close_on_click_away, :boolean, default: true
  attr :close_on_keydown, :boolean, default: true
  attr :rest, :global

  attr :on_close, JS, default: %JS{}
  attr :on_open, JS, default: %JS{}

  slot :inner_block, required: true
  slot :title
  slot :subtitle

  slot :footer do
    attr :class, :string
  end

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-on-close={hide_modal(@on_close, @id)}
      phx-hook="ModalHook"
      class={"#{@position} z-50 hidden"}
      {@rest}
    >
      <div
        id={"#{@id}-bg"}
        class="hidden fixed inset-0 bg-gray-900/60 backdrop-blur-sm transition-opacity"
        aria-hidden="true"
        phx-click={
          @close_on_click_away &&
            hide_modal(@on_close, @id)
        }
      />
      <div
        class="fixed inset-0 overflow-y-auto sm:py-2"
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
              phx-window-keydown={
                @close_on_keydown &&
                  hide_modal(@on_close, @id)
              }
              phx-key="escape"
              phx-click-away={
                @close_on_click_away &&
                  hide_modal(@on_close, @id)
              }
              class={[
                "hidden relative rounded-xl transition",
                "bg-white py-[24px] shadow-lg shadow-zinc-700/10 ring-1 ring-zinc-700/10"
              ]}
            >
              <header :if={@title != []} class="pl-[24px] pr-[24px]">
                <.modal_title id={"#{@id}-title"}>
                  {render_slot(@title)}
                  <:subtitle>
                    {render_slot(@subtitle)}
                  </:subtitle>
                </.modal_title>
              </header>
              <div :if={@title != []} class="flex-grow bg-gray-100 h-0.5 my-[16px]">
              </div>
              <section class="pl-[24px] pr-[24px]">
                {render_slot(@inner_block)}
              </section>
              <%= for footer <- @footer do %>
                <.modal_footer {if(footer[:class], do: [class: footer[:class]], else: [])}>
                  {render_slot(footer)}
                </.modal_footer>
              <% end %>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :rest, :global
  slot :subtitle
  slot :inner_block, required: true

  def modal_title(assigns) do
    ~H"""
    <h1 class="text-lg font-semibold leading-5 text-zinc-800" {@rest}>
      {render_slot(@inner_block)}
    </h1>
    <%= for subtitle <- @subtitle do %>
      <p class="mt-2 text-sm leading-4.5 text-zinc-600">
        {render_slot(subtitle)}
      </p>
    <% end %>
    """
  end

  attr :class, :any, default: "sm:flex sm:flex-row-reverse gap-3"
  slot :inner_block, required: true

  def modal_footer(assigns) do
    ~H"""
    <div class="mt-[16px]"></div>
    <footer class={@class}>
      {render_slot(@inner_block)}
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
    %JS{}
    |> JS.hide(
      to: "##{id}-bg",
      transition:
        {"transition-all transform ease-in duration-200", "opacity-100",
         "opacity-0"}
    )
    |> JS.hide(
      to: "##{id}-container",
      time: 50,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.concat(js)
    |> JS.pop_focus()
  end
end
