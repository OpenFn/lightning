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
    """
  end

  def profile_items(assigns) do
    ~H"""
    <.menu_item to={~p"/projects"} active={@active_menu_item == :projects}>
      <.icon name="hero-folder" class="h-5 w-5 inline-block mr-2" /> Projects
    </.menu_item>
    <.menu_item to={~p"/profile"} active={@active_menu_item == :profile}>
      <.icon name="hero-user-circle" class="h-5 w-5 inline-block mr-2" />
      User Profile
    </.menu_item>
    <.menu_item to={~p"/credentials"} active={@active_menu_item == :credentials}>
      <.icon name="hero-key" class="h-5 w-5 inline-block mr-2" /> Credentials
    </.menu_item>
    <.menu_item to={~p"/profile/tokens"} active={@active_menu_item == :tokens}>
      <.icon name="hero-command-line" class="h-5 w-5 inline-block mr-2" /> API Tokens
    </.menu_item>
    """
  end

  def menu_item(assigns) do
    # base_classes =
    #   [
    #     "menu-item px-3 py-2 rounded-md text-sm font-medium rounded-md block",
    #     "data-[active]:text-[--primary-text-lighter]",
    #     "data-[active]:bg-[--primary-bg-dark]",
    #     "[&:not([data-active])]:text-[--primary-text-light]",
    #     "[&:not([data-active])]:hover:bg-[--primary-bg-dark]"
    #   ]

    # active_classes = ~w[menu-item-active] ++ base_classes

    # inactive_classes = ~w[menu-item-inactive] ++ base_classes

    assigns =
      assigns
      |> assign_new(:target, fn -> "_blank" end)

    ~H"""
    <div class="h-12 mx-2">
      <%= if assigns[:href] do %>
        <.link
          href={@href}
          target={@target}
          class={"menu-item px-3 py-2 rounded-md text-sm font-medium rounded-md block text-[--primary-text-light] hover:bg-[--primary-bg-dark]"}
        >
          <%= if assigns[:inner_block] do %>
            <%= render_slot(@inner_block) %>
          <% else %>
            <%= @text %>
          <% end %>
        </.link>
      <% else %>
        <.link
          navigate={@to}
          data-active={@active}
          class={[
            "menu-item px-3 py-2 rounded-md text-sm font-medium rounded-md block",
            "data-[active]:text-[--primary-text-lighter]",
            "data-[active]:bg-[--primary-bg-dark]",
            "[&:not([data-active])]:text-[--primary-text-light]",
            "[&:not([data-active])]:hover:bg-[--primary-bg-dark]"
          ]}
        >
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
