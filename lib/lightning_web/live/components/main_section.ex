defmodule LightningWeb.Components.MainSection do
  @moduledoc """
  Wrapper helpers for layout
  """
  use LightningWeb, :component

  def header(assigns) do
    ~H"""
    <header class="bg-white shadow">
      <div class="max-w-7xl mx-auto h-20 sm:px-6 lg:px-8 flex items-center">
        <h1 class="text-3xl font-bold text-gray-900">
          <%= @title %>
        </h1>
        <div class="grow"></div>
        <%= if assigns[:inner_block], do: render_slot(@inner_block) %>
      </div>
    </header>
    """
  end

  def main(assigns) do
    ~H"""
    <section id="inner">
      <div class="max-w-7xl mx-auto py-6 sm:px-6 lg:px-8">
        <%= render_slot(@inner_block) %>
      </div>
    </section>
    """
  end
end
