defmodule LightningWeb.Components.Menu do
  @moduledoc """
  Menu components to render menu items for project and user/profile pages.
  """
  use LightningWeb, :component

  attr :project_id, :string, required: true
  attr :current_user, :map, required: true
  attr :active_menu_item, :atom, required: true
  attr :collapsed, :boolean, default: false

  def project_items(assigns) do
    ~H"""
    <.menu_item
      to={~p"/projects/#{@project_id}/w"}
      active={@active_menu_item == :overview}
      collapsed={@collapsed}
    >
      <Icon.workflows class="h-5 w-5 inline-block mr-2 align-middle" />
      <span class="inline-block align-middle menu-item-text">Workflows</span>
    </.menu_item>

    <%= if Lightning.Accounts.experimental_features_enabled?(@current_user) do %>
      <.menu_item
        to={~p"/projects/#{@project_id}/sandboxes"}
        active={@active_menu_item == :sandboxes}
        collapsed={@collapsed}
      >
        <Icon.sandboxes class="h-5 w-5 inline-block mr-2 align-middle" />
        <span class="inline-block align-middle menu-item-text">Sandboxes</span>
      </.menu_item>
    <% end %>

    <.menu_item
      to={~p"/projects/#{@project_id}/history"}
      active={@active_menu_item == :runs}
      collapsed={@collapsed}
    >
      <Icon.runs class="h-5 w-5 inline-block mr-2" />
      <span class="inline-block align-middle menu-item-text">History</span>
    </.menu_item>

    <.menu_item
      to={"/projects/#{@project_id}/settings"}
      active={@active_menu_item == :settings}
      collapsed={@collapsed}
    >
      <Icon.settings class="h-5 w-5 inline-block mr-2" />
      <span class="inline-block align-middle menu-item-text">Settings</span>
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

  attr :active_menu_item, :atom, required: true
  attr :collapsed, :boolean, default: false

  def profile_items(assigns) do
    ~H"""
    <.menu_item
      to={~p"/projects"}
      active={@active_menu_item == :projects}
      collapsed={@collapsed}
    >
      <Heroicons.folder class="h-5 w-5 inline-block mr-2" />
      <span class="menu-item-text">Projects</span>
    </.menu_item>
    <.menu_item
      to={~p"/profile"}
      active={@active_menu_item == :profile}
      collapsed={@collapsed}
    >
      <Heroicons.user_circle class="h-5 w-5 inline-block mr-2" />
      <span class="menu-item-text">User Profile</span>
    </.menu_item>
    <.menu_item
      to={~p"/credentials"}
      active={@active_menu_item == :credentials}
      collapsed={@collapsed}
    >
      <Heroicons.key class="h-5 w-5 inline-block mr-2" />
      <span class="menu-item-text">Credentials</span>
    </.menu_item>
    <.menu_item
      to={~p"/profile/tokens"}
      active={@active_menu_item == :tokens}
      collapsed={@collapsed}
    >
      <Heroicons.command_line class="h-5 w-5 inline-block mr-2" />
      <span class="menu-item-text">API Tokens</span>
    </.menu_item>
    """
  end

  attr :to, :string, default: nil
  attr :href, :string, default: nil
  attr :active, :boolean, default: false
  attr :collapsed, :boolean, default: false
  attr :target, :string, default: "_blank"
  attr :text, :string, default: nil
  slot :inner_block

  def menu_item(assigns) do
    base_classes =
      ~w[menu-item px-3 py-2 rounded-md text-sm font-medium rounded-md block flex items-center]

    active_classes = ~w[menu-item-active] ++ base_classes

    inactive_classes = ~w[menu-item-inactive] ++ base_classes

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
    <div class={["h-12 mx-3"]}>
      <%= if assigns[:href] do %>
        <.link href={@href} target={@target} class={@class}>
          <%= if assigns[:inner_block] do %>
            {render_slot(@inner_block)}
          <% else %>
            {@text}
          <% end %>
        </.link>
      <% else %>
        <.link navigate={@to} class={@class}>
          <%= if assigns[:inner_block] do %>
            {render_slot(@inner_block)}
          <% else %>
            {@text}
          <% end %>
        </.link>
      <% end %>
    </div>
    """
  end
end
