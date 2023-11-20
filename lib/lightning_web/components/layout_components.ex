defmodule LightningWeb.LayoutComponents do
  @moduledoc false
  use LightningWeb, :html

  import PetalComponents.Dropdown
  import PetalComponents.Avatar

  def menu_items(assigns) do
    ~H"""
    <%= if assigns[:project] do %>
      <div class="p-2 mb-4 mt-4 text-center text-primary-300 bg-primary-800">
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
      <%= if assigns[:projects] do %>
        <div class="p-2 mb-4 mt-4 text-center text-primary-300 bg-primary-800">
          <%= if Enum.count(@projects) >= 1 do %>
            <.dropdown placement="right" label="Go to project" js_lib="live_view_js">
              <%= for project <- @projects do %>
                <.dropdown_menu_item
                  link_type="live_redirect"
                  to={~p"/projects/#{project.id}/w"}
                  label={project.name}
                />
              <% end %>
            </.dropdown>
          <% else %>
            <span class="inline-block align-middle text-sm">
              You don't have access to any projects
            </span>
          <% end %>
        </div>
      <% else %>
        <div class="mb-4" />
      <% end %>
    <% end %>

    <%= if assigns[:project] do %>
      <Settings.menu_item
        to={~p"/projects/#{@project.id}/w"}
        active={@active_menu_item == :overview}
      >
        <Icon.workflows class="h-5 w-5 inline-block mr-2 align-middle" />
        <span class="inline-block align-middle">Workflows</span>
      </Settings.menu_item>

      <Settings.menu_item
        to={Routes.project_run_index_path(@socket, :index, @project.id)}
        active={@active_menu_item == :runs}
      >
        <Icon.runs class="h-5 w-5 inline-block mr-2" />
        <span class="inline-block align-middle">History</span>
      </Settings.menu_item>

      <Settings.menu_item
        to={Routes.project_project_settings_path(@socket, :index, @project.id)}
        active={@active_menu_item == :settings}
      >
        <Icon.settings class="h-5 w-5 inline-block mr-2" />
        <span class="inline-block align-middle">Settings</span>
      </Settings.menu_item>
      <!-- # Commented out until new dataclips/globals list is fully functional. -->
    <!-- <Settings.menu_item
      to={Routes.project_dataclip_index_path(@socket, :index, @project.id)}
      active={@active_menu_item == :dataclips}
    >
      <Icon.dataclips class="h-5 w-5 inline-block mr-2" />
      <span class="inline-block align-middle">Dataclips</span>
    </Settings.menu_item> -->
    <% else %>
      <Settings.menu_item to={~p"/profile"} active={@active_menu_item == :profile}>
        <Heroicons.user_circle class="h-5 w-5 inline-block mr-2" /> User Profile
      </Settings.menu_item>
      <Settings.menu_item
        to={~p"/credentials"}
        active={@active_menu_item == :credentials}
      >
        <Heroicons.key class="h-5 w-5 inline-block mr-2" /> Credentials
      </Settings.menu_item>
      <Settings.menu_item
        to={~p"/profile/tokens"}
        active={@active_menu_item == :tokens}
      >
        <Heroicons.command_line class="h-5 w-5 inline-block mr-2" /> API Tokens
      </Settings.menu_item>
    <% end %>
    """
  end

  # https://play.tailwindcss.com/r7kBDT2cJY?layout=horizontal
  def page_content(assigns) do
    ~H"""
    <div class="flex h-full w-full flex-col">
      <%= if assigns[:header], do: render_slot(@header) %>
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
    <div class="flex-none bg-white shadow-sm">
      <div class="max-w-7xl mx-auto h-20 sm:px-6 lg:px-8 flex items-center">
        <h1 class="text-3xl font-bold text-secondary-900 flex items-center grow">
          <%= if assigns[:title], do: render_slot(@title) %>
        </h1>
        <div class="grow"></div>
        <%= if assigns[:inner_block], do: render_slot(@inner_block) %>
        <%= if assigns[:current_user] do %>
          <div class="w-5" />
          <.dropdown js_lib="live_view_js">
            <:trigger_element>
              <div class="inline-flex items-center justify-center w-full align-middle focus:outline-none">
                <.avatar
                  size="sm"
                  name={
                    String.at(@current_user.first_name, 0) <>
                      if is_nil(@current_user.last_name),
                        do: "",
                        else: String.at(@current_user.last_name, 0)
                  }
                />
                <Heroicons.chevron_down
                  solid
                  class="w-4 h-4 ml-1 -mr-1 text-secondary-400 dark:text-secondary-100"
                />
              </div>
            </:trigger_element>
            <.dropdown_menu_item link_type="live_redirect" to={~p"/profile"}>
              <Heroicons.user_circle class="w-5 h-5 text-secondary-500" />
              User Profile
            </.dropdown_menu_item>
            <.dropdown_menu_item link_type="live_redirect" to={~p"/credentials"}>
              <Heroicons.key class="w-5 h-5 text-secondary-500" /> Credentials
            </.dropdown_menu_item>
            <.dropdown_menu_item link_type="live_redirect" to={~p"/profile/tokens"}>
              <Heroicons.command_line class="w-5 h-5 text-secondary-500" />
              API Tokens
            </.dropdown_menu_item>
            <.dropdown_menu_item link_type="live_redirect" to={~p"/users/log_out"}>
              <Heroicons.arrow_right_on_rectangle class="w-5 h-5 text-secondary-500" />
              Log out
            </.dropdown_menu_item>
          </.dropdown>
        <% end %>
      </div>
    </div>
    """
  end

  attr :class, :string, default: ""
  slot :inner_block, required: true

  def centered(assigns) do
    ~H"""
    <div class={["max-w-7xl mx-auto py-6 sm:px-6 lg:px-8", @class]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  def nav(assigns) do
    ~H"""
    <nav class="bg-secondary-800">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex items-center justify-between h-16">
          <div class="flex items-center">
            <div class="flex-shrink-0">
              <img
                class="h-8 w-8"
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
