require Lightning.BuildMacros

Lightning.BuildMacros.do_in [:dev, :test] do
  defmodule LightningWeb.Dev.ReactLive do
    # Internal Development Page for viewing and working on React components.
    # Access this page at /dev/react
    @moduledoc false
    use LightningWeb, {:live_view, layout: {LightningWeb.Layouts, :blank}}

    import React

    @impl true
    def mount(_params, _session, socket) do
      socket = assign(socket, :foo, 0)
      {:ok, socket}
    end

    @impl true
    def handle_event("inc", _params, socket) do
      {:noreply, update(socket, :foo, &(&1 + 1))}
    end

    attr :foo, :integer
    jsx("assets/js/react/components/Foo.tsx")

    jsx("assets/js/react/components/Bar.tsx")

    jsx("assets/js/react/components/Baz.tsx")

    @impl true
    def render(assigns) do
      ~H"""
      <.Bar react-portal-target="foo" react-id="bar" />
      <.Foo foo={@foo} react-id="foo" />
      <.Baz react-portal-target="bar" />
      <button
        phx-click="inc"
        class="inline-flex justify-center items-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 phx-submit-loading:opacity-75 bg-primary-600 hover:bg-primary-700 text-white focus:ring-primary-500 disabled:bg-primary-300 rounded-md"
      >
        Increment
      </button>
      """
    end
  end
end
