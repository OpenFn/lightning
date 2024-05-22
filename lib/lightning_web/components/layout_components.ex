defmodule LightningWeb.LayoutComponents do
  @moduledoc false
  use LightningWeb, :html

  alias LightningWeb.Components.Menu

  import PetalComponents.Dropdown
  import PetalComponents.Avatar

  def scope(active_menu_item, selected_project, custom_scopes) do
    cond do
      active_menu_item in [:profile, :tokens, :credentials] -> :user_scope
      selected_project != nil -> :project_scope
      true -> Map.get(custom_scopes, active_menu_item, :none)
    end
  end

  def menu_items(assigns) do
    custom_menu_items =
      Application.get_env(:lightning, :menu_items, [])

    scope =
      scope(
        assigns[:active_menu_item],
        assigns[:project],
        custom_menu_items[:active_item_custom_scope]
      )

    assigns =
      assign(assigns,
        custom_scope_menu: custom_menu_items[scope],
        scope: scope
      )

    ~H"""
    <%= if assigns[:projects] do %>
      <Menu.projects_dropdown
        projects={assigns[:projects]}
        selected_project={assigns[:project]}
        active_menu_item={assigns[:active_menu_item]}
      />
    <% else %>
      <div class="p-2 mb-4 mt-4 text-center text-primary-300 bg-primary-800">
        <span class="inline-block align-middle text-sm">
          You don't have access to any projects
        </span>
      </div>
    <% end %>

    <%= cond do %>
      <% @scope == :user_scope -> %>
        <Menu.profile_items active_menu_item={@active_menu_item} />
      <% @scope == :project_scope and assigns[:custom_scope_menu] -> %>
        <%= Phoenix.LiveView.TagEngine.component(
          @custom_scope_menu.component,
          Map.take(assigns, @custom_scope_menu.assigns_keys),
          {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
        ) %>
      <% @scope == :project_scope -> %>
        <Menu.project_items
          project_id={@project.id}
          active_menu_item={@active_menu_item}
        />
      <% Map.has_key?(assigns, :custom_scope_menu) -> %>
        <%= Phoenix.LiveView.TagEngine.component(
          @custom_scope_menu.component,
          Map.take(assigns, @custom_scope_menu.assigns_keys),
          {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
        ) %>
      <% true -> %>
        <% :ok %>
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
