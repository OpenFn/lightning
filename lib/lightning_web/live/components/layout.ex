defmodule LightningWeb.Components.Layout do
  @moduledoc false
  use LightningWeb, :component

  # https://play.tailwindcss.com/r7kBDT2cJY?layout=horizontal
  def page_content(assigns) do
    ~H"""
    <div class="flex h-full w-full flex-col">
      <%= render_slot(@header) %>
      <div class="flex-auto bg-secondary-100 relative">
        <section
          id="inner_content"
          class="overflow-y-auto absolute top-0 bottom-0 left-0 right-0"
        >
          <%= render_slot(@inner_block) %>
        </section>
      </div>
    </div>
    """
  end

  def header(assigns) do
    ~H"""
    <div class="flex-none bg-white shadow-sm z-10">
      <div class="max-w-7xl mx-auto h-20 sm:px-6 lg:px-8 flex items-center">
        <h1 class="text-3xl font-bold text-secondary-900">
          <%= @title %>
        </h1>
        <div class="grow"></div>
        <%= if assigns[:inner_block], do: render_slot(@inner_block) %>
        <%= if assigns[:socket] do %>
          <div class="w-5" />
          <.dropdown js_lib="live_view_js">
            <:trigger_element>
              <div class="inline-flex items-center justify-center w-full align-middle focus:outline-none">
                <.avatar size="sm" />
                <Heroicons.Solid.chevron_down class="w-4 h-4 ml-1 -mr-1 text-secondary-400 dark:text-secondary-100" />
              </div>
            </:trigger_element>
            <.dropdown_menu_item
              link_type="live_redirect"
              to={Routes.profile_edit_path(@socket, :edit)}
            >
              <Heroicons.Outline.cog class="w-5 h-5 text-secondary-500" />
              User Profile
            </.dropdown_menu_item>
            <.dropdown_menu_item
              link_type="live_redirect"
              to={Routes.credential_index_path(@socket, :index)}
            >
              <Heroicons.Outline.key class="w-5 h-5 text-secondary-500" />
              Credentials
            </.dropdown_menu_item>
            <.dropdown_menu_item
              link_type="live_redirect"
              to={Routes.user_session_path(@socket, :delete)}
            >
              <Heroicons.Outline.logout class="w-5 h-5 text-secondary-500" /> Logout
            </.dropdown_menu_item>
          </.dropdown>
        <% end %>
      </div>
    </div>
    """
  end

  def centered(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto py-6 sm:px-6 lg:px-8">
      <%= render_slot(@inner_block) %>
    </div>
    """
  end
end
