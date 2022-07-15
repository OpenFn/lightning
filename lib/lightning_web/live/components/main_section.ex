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
        <%= if @socket do %>
          <div class="w-5" />
          <.dropdown js_lib="live_view_js">
            <:trigger_element>
              <div class="inline-flex items-center justify-center w-full align-middle focus:outline-none">
                <.avatar size="sm" />
                <Heroicons.Solid.chevron_down class="w-4 h-4 ml-1 -mr-1 text-gray-400 dark:text-gray-100" />
              </div>
            </:trigger_element>
            <.dropdown_menu_item
              link_type="live_redirect"
              to={Routes.user_settings_path(@socket, :edit)}
              label="User Profile"
            />
            <.dropdown_menu_item
              link_type="live_redirect"
              to={Routes.user_session_path(@socket, :delete)}
              label="Logout"
            />
          </.dropdown>
        <% end %>
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
