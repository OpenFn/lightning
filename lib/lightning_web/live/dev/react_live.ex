defmodule LightningWeb.Dev.ReactLive do
  # Internal Development Page for viewing and working on React components.
  # Access this page at /dev/react
  @moduledoc false
  use LightningWeb, {:live_view, layout: {LightningWeb.Layouts, :blank}}

  import React
  use React.Component

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  jsx("components/Foo.tsx")
  jsx("components/Bar.tsx")

  @impl true
  def render(assigns) do
    ~H"""
    <.Foo />
    <.Bar />
    """
  end
end
