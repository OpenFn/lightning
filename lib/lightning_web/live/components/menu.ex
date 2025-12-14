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
      tooltip="Workflows"
    >
      <Icon.workflows class="h-5 w-5 inline-block mr-2 align-middle" />
      <span class="inline-block align-middle menu-item-text">Workflows</span>
    </.menu_item>

    <%= if Lightning.Accounts.experimental_features_enabled?(@current_user) do %>
      <.menu_item
        to={~p"/projects/#{@project_id}/sandboxes"}
        active={@active_menu_item == :sandboxes}
        collapsed={@collapsed}
        tooltip="Sandboxes"
      >
        <Icon.sandboxes class="h-5 w-5 inline-block mr-2 align-middle" />
        <span class="inline-block align-middle menu-item-text">Sandboxes</span>
      </.menu_item>
    <% end %>

    <.menu_item
      to={~p"/projects/#{@project_id}/history"}
      active={@active_menu_item == :runs}
      collapsed={@collapsed}
      tooltip="History"
    >
      <Icon.runs class="h-5 w-5 inline-block mr-2" />
      <span class="inline-block align-middle menu-item-text">History</span>
    </.menu_item>

    <.menu_item
      to={"/projects/#{@project_id}/settings"}
      active={@active_menu_item == :settings}
      collapsed={@collapsed}
      tooltip="Settings"
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
      tooltip="Projects"
    >
      <Heroicons.folder class="h-5 w-5 inline-block mr-2" />
      <span class="menu-item-text">Projects</span>
    </.menu_item>
    <.menu_item
      to={~p"/profile"}
      active={@active_menu_item == :profile}
      collapsed={@collapsed}
      tooltip="User Profile"
    >
      <Heroicons.user_circle class="h-5 w-5 inline-block mr-2" />
      <span class="menu-item-text">User Profile</span>
    </.menu_item>
    <.menu_item
      to={~p"/credentials"}
      active={@active_menu_item == :credentials}
      collapsed={@collapsed}
      tooltip="Credentials"
    >
      <Heroicons.key class="h-5 w-5 inline-block mr-2" />
      <span class="menu-item-text">Credentials</span>
    </.menu_item>
    <.menu_item
      to={~p"/profile/tokens"}
      active={@active_menu_item == :tokens}
      collapsed={@collapsed}
      tooltip="API Tokens"
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
  attr :tooltip, :string, default: nil
  attr :target, :string, default: "_blank"
  attr :text, :string, default: nil
  slot :inner_block

  def menu_item(assigns) do
    base_classes =
      ~w[menu-item px-3 py-2 rounded-md text-sm font-medium rounded-md block]

    active_classes = ~w[menu-item-active] ++ base_classes

    inactive_classes = ~w[menu-item-inactive] ++ base_classes

    collapsed_classes = ~w[menu-item-collapsed flex justify-center items-center]

    assigns =
      assigns
      |> assign(
        class:
          if assigns[:active] do
            if assigns[:collapsed],
              do: active_classes ++ collapsed_classes,
              else: active_classes
          else
            if assigns[:collapsed],
              do: inactive_classes ++ collapsed_classes,
              else: inactive_classes
          end
      )
      |> assign_new(:target, fn -> "_blank" end)
      |> assign_new(:id, fn ->
        "menu-item-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
      end)

    ~H"""
    <div
      id={if @collapsed && @tooltip, do: @id, else: nil}
      class={["h-12", !@collapsed && "mx-3", @collapsed && "mx-2"]}
      phx-hook={if @collapsed && @tooltip, do: "Tooltip", else: nil}
      aria-label={if @collapsed && @tooltip, do: @tooltip, else: nil}
      data-placement={if @collapsed && @tooltip, do: "right", else: nil}
    >
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
