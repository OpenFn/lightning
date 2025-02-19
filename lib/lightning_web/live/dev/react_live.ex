defmodule LightningWeb.Dev.ReactLive do
  # Internal Development Page for viewing and working on React components.
  # Access this page at /dev/react
  @moduledoc false
  use LightningWeb, {:live_view, layout: {LightningWeb.Layouts, :blank}}

  import React

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, :baz, 0)
    {:ok, socket}
  end

  @impl true
  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :baz, &(&1 + 1))}
  end

  attr :foo, :integer
  slot :inner_block
  jsx("components/Foo.tsx")

  slot :before
  slot :inner_block, required: true
  slot :after, required: true
  jsx("components/Bar.tsx")

  attr :baz, :integer, default: 0
  jsx("components/Baz.tsx")

  @impl true
  def render(assigns) do
    assigns = assign(assigns, foo: 42)

    ~H"""
    <.Foo foo={@foo}>
      <.Bar>
        <:before>
          <p style="color: blue">Bar before slot</p>
        </:before>
        <.Baz baz={@baz} />
        <:after>
          <p style="color: red">Bar after slot</p>
        </:after>
      </.Bar>
    </.Foo>
    <button
      phx-click="inc"
      class="inline-flex justify-center items-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 phx-submit-loading:opacity-75 bg-primary-600 hover:bg-primary-700 text-white focus:ring-primary-500 disabled:bg-primary-300 rounded-md"
    >
      Increment
    </button>
    """
  end
end
