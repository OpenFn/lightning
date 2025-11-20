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

    <%= if Lightning.Accounts.experimental_features_enabled?(@current_user) do %>
      <.menu_item
        to={~p"/projects/#{@project_id}/sandboxes"}
        active={@active_menu_item == :sandboxes}
      >
        <Icon.sandboxes class="h-5 w-5 inline-block mr-2 align-middle" />
        <span class="inline-block align-middle">Sandboxes</span>
      </.menu_item>
    <% end %>

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

  def menu_item(assigns) do
    base_classes =
      ~w[menu-item px-3 py-2 rounded-md text-sm font-medium rounded-md block]

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
    <div class="h-12 mx-3">
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
