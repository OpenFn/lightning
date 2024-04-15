defmodule LightningWeb.LayoutComponents do
  @moduledoc false
  use LightningWeb, :html

  import PetalComponents.Dropdown
  import PetalComponents.Avatar

  def menu_items(assigns) do
    custom_menu_items =
      Application.get_env(:lightning, :menu_items, [])
      |> Enum.filter(fn {assign_set, _items} ->
        not is_nil(assigns[assign_set])
      end)
      |> Enum.flat_map(fn {_assign_set, items} -> items end)

    if Enum.empty?(custom_menu_items) do
      default_menu_items(assigns)
    else
      assigns = assign(assigns, custom_menu_items: custom_menu_items)

      ~H"""
      <div class="mt-4">
        <%= for {to, icon, text, menu_item} <- @custom_menu_items do %>
          <Settings.menu_item to={to} active={@active_menu_item == menu_item}>
            <%= Phoenix.LiveView.TagEngine.component(
              icon,
              [class: "h-5 w-5 inline-block mr-1"],
              {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
            ) %>
            <span class="inline-block align-middle"><%= text %></span>
          </Settings.menu_item>
        <% end %>
      </div>
      """
    end
  end

  def default_menu_items(assigns) do
    ~H"""
    <%= if assigns[:projects] do %>
      <div class="relative my-4 mx-2 px-2">
        <button
          type="button"
          class="relative w-full cursor-default rounded-md bg-white py-1.5 pl-3
          pr-10 text-left text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300
          focus:outline-none focus:ring-2 focus:ring-indigo-600 sm:text-sm sm:leading-6"
          aria-haspopup="listbox"
          aria-expanded="true"
          aria-labelledby="listbox-label"
          phx-click={show_dropdown("project-picklist")}
        >
          <span class="block truncate">
            <%= if assigns[:project], do: @project.name, else: "Go to project" %>
          </span>
          <span class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-2">
            <svg
              class="h-5 w-5 text-gray-400"
              viewBox="0 0 20 20"
              fill="currentColor"
              aria-hidden="true"
            >
              <path
                fill-rule="evenodd"
                d="M10 3a.75.75 0 01.55.24l3.25 3.5a.75.75 0 11-1.1 1.02L10 4.852 7.3 7.76a.75.75 0 01-1.1-1.02l3.25-3.5A.75.75 0 0110 3zm-3.76 9.2a.75.75 0 011.06.04l2.7 2.908 2.7-2.908a.75.75 0 111.1 1.02l-3.25 3.5a.75.75 0 01-1.1 0l-3.25-3.5a.75.75 0 01.04-1.06z"
                clip-rule="evenodd"
              />
            </svg>
          </span>
        </button>
        <ul
          id="project-picklist"
          class="hidden absolute z-10 mt-1 max-h-60 w-full overflow-auto rounded-md bg-white py-1 text-base shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none sm:text-sm"
          tabindex="-1"
          role="listbox"
          aria-labelledby="listbox-label"
          aria-activedescendant="listbox-option-3"
          phx-click-away={hide_dropdown("project-picklist")}
        >
          <%= for project <- @projects do %>
            <.link navigate={~p"/projects/#{project.id}/w"}>
              <li
                class={[
                  "text-gray-900 relative cursor-default select-none py-2 pl-3 pr-9 hover:bg-indigo-600 group hover:text-white"
                ]}
                role="option"
              >
                <span class={[
                  "font-normal block truncate",
                  assigns[:project] && @project.id == project.id && "font-semibold"
                ]}>
                  <%= project.name %>
                </span>
                <span class={[
                  "absolute inset-y-0 right-0 flex items-center pr-4",
                  (!assigns[:project] || @project.id != project.id) && "hidden"
                ]}>
                  <.icon
                    name="hero-check"
                    class="group-hover:text-white text-indigo-600"
                  />
                </span>
              </li>
            </.link>
          <% end %>
        </ul>
      </div>
    <% else %>
      <div class="p-2 mb-4 mt-4 text-center text-primary-300 bg-primary-800">
        <span class="inline-block align-middle text-sm">
          You don't have access to any projects
        </span>
      </div>
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
      <%= if assigns[:banner], do: render_slot(@banner) %>
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

  attr :current_user, Lightning.Accounts.User
  attr :socket, Phoenix.LiveView.Socket
  slot :title
  slot :period
  slot :description
  slot :inner_block

  def header(assigns) do
    title_height =
      if Enum.any?(assigns[:description]) do
        "mt-4 h-10"
      else
        "h-20"
      end

    # description has the same title class except for height and font
    assigns =
      assign(assigns,
        title_class: "max-w-7xl mx-auto sm:px-6 lg:px-8",
        title_height: "py-6 flex items-center " <> title_height
      )

    ~H"""
    <div class="flex-none bg-white shadow-sm">
      <div class={[@title_class, @title_height]}>
        <h1 class="text-3xl font-bold text-secondary-900 flex items-center">
          <%= if assigns[:title], do: render_slot(@title) %>
        </h1>
        <%= if assigns[:period] do %>
          <span class="ml-2 mt-3 text-xs">
            <%= render_slot(@period) %>
          </span>
        <% end %>
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
      <%= if Enum.any?(assigns[:description]) do %>
        <div class={[@title_class, "h-6 text-sm"]}>
          <%= render_slot(@description) %>
        </div>
      <% end %>
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
