defmodule LightningWeb.Components.Menu do
  @moduledoc """
  Menu components to render menu items for project and user/profile pages.
  """
  use LightningWeb, :component

  def project_items(assigns) do
    ~H"""
    <.menu_item
      to={~p"/projects/#{@project_id}/w"}
      active={@active_menu_item == :overview}
    >
      <Icon.workflows class="h-5 w-5 inline-block mr-2 align-middle" />
      <span class="inline-block align-middle">Workflows</span>
    </.menu_item>

    <.menu_item
      to={~p"/projects/#{@project_id}/history"}
      active={@active_menu_item == :runs}
    >
      <Icon.runs class="h-5 w-5 inline-block mr-2" />
      <span class="inline-block align-middle">History</span>
    </.menu_item>

    <.menu_item
      to={"/projects/#{@project_id}/settings"}
      active={@active_menu_item == :settings}
    >
      <Icon.settings class="h-5 w-5 inline-block mr-2" />
      <span class="inline-block align-middle">Settings</span>
    </.menu_item>
    <!-- # Commented out until new dataclips/globals list is fully functional. -->
    <!--
      <.menu_item
        to={Routes.project_dataclip_index_path(@socket, :index, @project.id)}
        active={@active_menu_item == :dataclips}>
        <Icon.dataclips class="h-5 w-5 inline-block mr-2" />
        <span class="inline-block align-middle">Dataclips</span>
      </.menu_item>
    -->
    """
  end

  def profile_items(assigns) do
    ~H"""
    <.menu_item to={~p"/projects"} active={@active_menu_item == :projects}>
      <Heroicons.folder class="h-5 w-5 inline-block mr-2" /> Projects
    </.menu_item>
    <.menu_item to={~p"/profile"} active={@active_menu_item == :profile}>
      <Heroicons.user_circle class="h-5 w-5 inline-block mr-2" /> User Profile
    </.menu_item>
    <.menu_item to={~p"/credentials"} active={@active_menu_item == :credentials}>
      <Heroicons.key class="h-5 w-5 inline-block mr-2" /> Credentials
    </.menu_item>
    <.menu_item to={~p"/profile/tokens"} active={@active_menu_item == :tokens}>
      <Heroicons.command_line class="h-5 w-5 inline-block mr-2" /> API Tokens
    </.menu_item>
    """
  end

  def projects_dropdown(assigns) do
    ~H"""
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
          <%= if assigns[:selected_project],
            do: @selected_project.name,
            else: "Go to project" %>
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
    """
  end

  def menu_item(assigns) do
    base_classes = ~w[px-3 py-2 rounded-md text-sm font-medium rounded-md block]

    active_classes = ~w[text-primary-200 bg-primary-900] ++ base_classes

    inactive_classes = ~w[text-primary-300 hover:bg-primary-900] ++ base_classes

    assigns =
      assigns
      |> assign(
        class:
          if assigns[:active] do
            active_classes
          else
            inactive_classes
          end
      )
      |> assign_new(:target, fn -> "_blank" end)

    ~H"""
    <div class="h-12 mx-2">
      <%= if assigns[:href] do %>
        <.link href={@href} target={@target} class={@class}>
          <%= if assigns[:inner_block] do %>
            <%= render_slot(@inner_block) %>
          <% else %>
            <%= @text %>
          <% end %>
        </.link>
      <% else %>
        <.link navigate={@to} class={@class}>
          <%= if assigns[:inner_block] do %>
            <%= render_slot(@inner_block) %>
          <% else %>
            <%= @text %>
          <% end %>
        </.link>
      <% end %>
    </div>
    """
  end
end
