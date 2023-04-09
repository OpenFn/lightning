defmodule LightningWeb.LayoutComponents do
  @moduledoc false
  use LightningWeb, :html

  import PetalComponents.Dropdown
  import PetalComponents.Avatar

  def menu_items(assigns) do
    ~H"""
    <%= if assigns[:project] do %>
      <div class="p-2 mt-4 mb-4 text-center text-primary-300 bg-primary-800">
        <%= if Enum.count(@projects) > 1 do %>
          <.dropdown placement="right" label={@project.name} js_lib="live_view_js">
            <%= for project <- @projects do %>
              <%= unless project.id == @project.id do %>
                <.dropdown_menu_item
                  link_type="live_redirect"
                  to={~p"/projects/#{project.id}/w"}
                  label={project.name}
                />
              <% end %>
            <% end %>
          </.dropdown>
        <% else %>
          <span class="inline-block align-middle"><%= @project.name %></span>
        <% end %>
      </div>
    <% else %>
      <div class="mb-4" />
    <% end %>

    <%= if assigns[:project] do %>
      <Settings.menu_item
        to={Routes.project_workflow_path(@socket, :index, @project.id)}
        active={@active_menu_item == :overview}
      >
        <Icon.workflows class="inline-block w-5 h-5 mr-2 align-middle" />
        <span class="inline-block align-middle">Workflows</span>
      </Settings.menu_item>

      <Settings.menu_item
        to={Routes.project_run_index_path(@socket, :index, @project.id)}
        active={@active_menu_item == :runs}
      >
        <Icon.runs class="inline-block w-5 h-5 mr-2" />
        <span class="inline-block align-middle">History</span>
      </Settings.menu_item>

      <Settings.menu_item
        to={Routes.project_project_settings_path(@socket, :index, @project.id)}
        active={@active_menu_item == :settings}
      >
        <Icon.settings class="inline-block w-5 h-5 mr-2" />
        <span class="inline-block align-middle">Settings</span>
      </Settings.menu_item>
      <!-- # Commented out until new dataclips/globals list is fully functional. -->
    <!-- <Settings.menu_item
      to={Routes.project_dataclip_index_path(@socket, :index, @project.id)}
      active={@active_menu_item == :dataclips}
    >
      <Icon.dataclips class="inline-block w-5 h-5 mr-2" />
      <span class="inline-block align-middle">Dataclips</span>
    </Settings.menu_item> -->
    <% else %>
      <Settings.menu_item to={Routes.profile_edit_path(@socket, :edit)}>
        <Heroicons.cog class="inline-block w-5 h-5 mr-2" /> User Profile
      </Settings.menu_item>
      <Settings.menu_item to={Routes.credential_index_path(@socket, :index)}>
        <Heroicons.key class="inline-block w-5 h-5 mr-2" /> Credentials
      </Settings.menu_item>

      <Settings.menu_item to={~p"/profile"}>
        <Heroicons.cog class="h-5 w-5 inline-block mr-2" /> User Profile
      </Settings.menu_item>
      <Settings.menu_item to={~p"/credentials"}>
        <Heroicons.key class="h-5 w-5 inline-block mr-2" /> Credentials
      </Settings.menu_item>
      <Settings.menu_item to={~p"/profile/tokens"}>
        <Heroicons.command_line class="h-5 w-5 inline-block mr-2" /> API Tokens
      </Settings.menu_item>
    <% end %>
    """
  end

  # https://play.tailwindcss.com/r7kBDT2cJY?layout=horizontal
  def page_content(assigns) do
    ~H"""
    <div class="flex flex-col w-full h-full">
      <%= if assigns[:header], do: render_slot(@header) %>
      <div class="relative flex-auto bg-secondary-100">
        <section
          id="inner_content"
          class="absolute top-0 bottom-0 left-0 right-0 overflow-y-auto"
        >
          <%= render_slot(@inner_block) %>
        </section>
      </div>
    </div>
    """
  end

  def header(assigns) do
    ~H"""
    <div class="z-20 flex-none bg-white shadow-sm">
      <div class="flex items-center w-3/4 h-20 mx-auto sm:px-6 lg:px-8">
        <h1 class="flex items-center text-3xl font-bold text-secondary-900">
          <%= if assigns[:title], do: render_slot(@title) %>
        </h1>
        <div class="grow"></div>
        <%= if assigns[:inner_block], do: render_slot(@inner_block) %>
        <%= if assigns[:socket] do %>
          <div class="w-5" />
          <.dropdown js_lib="live_view_js">
            <:trigger_element>
              <div class="inline-flex items-center justify-center w-full align-middle focus:outline-none">
                <.avatar size="sm" />
                <Heroicons.chevron_down
                  solid
                  class="w-4 h-4 ml-1 -mr-1 text-secondary-400 dark:text-secondary-100"
                />
              </div>
            </:trigger_element>
            <.dropdown_menu_item link_type="live_redirect" to={~p"/profile"}>
              <Heroicons.cog class="w-5 h-5 text-secondary-500" /> User Profile
            </.dropdown_menu_item>
            <.dropdown_menu_item link_type="live_redirect" to={~p"/credentials"}>
              <Heroicons.key class="w-5 h-5 text-secondary-500" /> Credentials
            </.dropdown_menu_item>
            <.dropdown_menu_item link_type="live_redirect" to={~p"/profile/tokens"}>
              <Heroicons.command_line class="w-5 h-5 text-secondary-500" />
              API Tokens
            </.dropdown_menu_item>
            <.dropdown_menu_item
              link_type="live_redirect"
              to={Routes.user_session_path(@socket, :delete)}
            >
              <Heroicons.arrow_right_on_rectangle class="w-5 h-5 text-secondary-500" />
              Log out
            </.dropdown_menu_item>
          </.dropdown>
        <% end %>
      </div>
    </div>
    """
  end

  def centered(assigns) do
    ~H"""
    <div class="w-3/4 py-6 mx-auto sm:px-6 lg:px-8">
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  def nav(assigns) do
    ~H"""
    <nav class="bg-secondary-800">
      <div class="px-4 mx-auto max-w-7xl sm:px-6 lg:px-8">
        <div class="flex items-center justify-between h-16">
          <div class="flex items-center">
            <div class="flex-shrink-0">
              <img
                class="w-8 h-8"
                src={Routes.static_path(@conn, "/images/square-logo.png")}
                alt="OpenFn"
              />
            </div>
          </div>
        </div>
      </div>
    </nav>
    """
  end
end
