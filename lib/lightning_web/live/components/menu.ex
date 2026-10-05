defmodule LightningWeb.Components.Menu do
  @moduledoc """
  Menu components to render menu items for project and user/profile pages.
  """
  use LightningWeb, :component

  import LightningWeb.Components.Icons

  attr :current_user, Lightning.Accounts.User, required: true

  @doc """
  Says that experimental features are on, on every page.

  The account menu says the same thing, but only once it is opened, and the
  setting people forget is the one they never open a menu to check. Links to
  the profile, where the switch is.
  """
  def experimental_mode_item(assigns) do
    ~H"""
    <div
      :if={Lightning.Accounts.experimental_features_enabled?(@current_user)}
      class="flex-shrink-0 border-t border-white/10 mt-3 pt-3"
    >
      <div class="mx-3">
        <LightningWeb.Components.Common.wrapper_tooltip
          id="experimental-mode-indicator"
          tooltip="You're using features that are still being built. Things may work differently for you than for your teammates."
          placement="right"
          class={~w[menu-item h-8 rounded-lg text-sm font-medium inline-flex
               items-center text-amber-300]}
        >
          <.icon name="hero-wrench-screwdriver" class="h-5 w-5 shrink-0" />
          <span class="menu-item-text truncate">Experimental</span>
        </LightningWeb.Components.Common.wrapper_tooltip>
      </div>
    </div>
    """
  end

  attr :project_id, :string, required: true
  attr :current_user, :map, required: true
  attr :active_menu_item, :atom, required: true

  def project_items(assigns) do
    ~H"""
    <.menu_item
      to={~p"/projects/#{@project_id}/w"}
      active={@active_menu_item == :overview}
    >
      <Icon.workflows class="h-5 w-5 shrink-0" />
      <span class="menu-item-text truncate">Workflows</span>
    </.menu_item>

    <%= if Lightning.Accounts.experimental_features_enabled?(@current_user) do %>
      <.menu_item
        to={~p"/projects/#{@project_id}/channels"}
        active={@active_menu_item == :channels}
      >
        <Icon.channels class="h-5 w-5 shrink-0" />
        <span class="menu-item-text truncate">Channels</span>
      </.menu_item>
    <% end %>
    <.menu_item
      to={~p"/projects/#{@project_id}/sandboxes"}
      active={@active_menu_item == :sandboxes}
    >
      <Icon.sandboxes class="h-5 w-5 shrink-0" />
      <span class="menu-item-text truncate">Sandboxes</span>
    </.menu_item>

    <.menu_item
      to={~p"/projects/#{@project_id}/history"}
      active={@active_menu_item == :runs}
    >
      <Icon.runs class="h-5 w-5 shrink-0" />
      <span class="menu-item-text truncate">History</span>
    </.menu_item>

    <.menu_item
      to={"/projects/#{@project_id}/settings"}
      active={@active_menu_item == :settings}
    >
      <Icon.settings class="h-5 w-5 shrink-0" />
      <span class="menu-item-text truncate">Settings</span>
    </.menu_item>
    """
  end

  attr :active_menu_item, :atom, required: true

  def profile_items(assigns) do
    ~H"""
    <.menu_item to={~p"/projects"} active={@active_menu_item == :projects}>
      <.icon name="hero-folder" class="h-5 w-5 shrink-0" />
      <span class="menu-item-text truncate">Projects</span>
    </.menu_item>
    <.menu_item to={~p"/profile"} active={@active_menu_item == :profile}>
      <.icon name="hero-user-circle" class="h-5 w-5 shrink-0" />
      <span class="menu-item-text truncate">User Profile</span>
    </.menu_item>
    <.menu_item to={~p"/credentials"} active={@active_menu_item == :credentials}>
      <.icon name="hero-key" class="h-5 w-5 shrink-0" />
      <span class="menu-item-text truncate">Credentials</span>
    </.menu_item>
    <.menu_item to={~p"/profile/tokens"} active={@active_menu_item == :tokens}>
      <.icon name="hero-command-line" class="h-5 w-5 shrink-0" />
      <span class="menu-item-text truncate">API Tokens</span>
    </.menu_item>
    """
  end

  attr :to, :string, default: nil
  attr :href, :string, default: nil
  attr :active, :boolean, default: false
  attr :target, :string, default: "_blank"
  attr :text, :string, default: nil
  slot :inner_block

  def menu_item(assigns) do
    base_classes =
      ~w[menu-item h-10 rounded-lg text-sm font-medium flex items-center
         transition-colors duration-150
         focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/30]

    assigns =
      assigns
      |> assign(
        class:
          if assigns[:active] do
            ~w[menu-item-active] ++ base_classes
          else
            ~w[menu-item-inactive] ++ base_classes
          end
      )
      |> assign_new(:target, fn -> "_blank" end)

    ~H"""
    <div class="h-10 mx-3 mb-1">
      <%= if assigns[:href] do %>
        <.link href={@href} target={@target} class={@class}>
          <%= if assigns[:inner_block] do %>
            {render_slot(@inner_block)}
          <% else %>
            {@text}
          <% end %>
        </.link>
      <% else %>
        <.link navigate={@to} class={@class} aria-current={@active && "page"}>
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
