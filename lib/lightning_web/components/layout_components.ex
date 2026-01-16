defmodule LightningWeb.LayoutComponents do
  @moduledoc false
  use LightningWeb, :html

  alias LightningWeb.Components.Menu
  alias Phoenix.LiveView.JS

  @doc """
  Renders a user avatar with initials.

  ## Examples

      <.user_avatar first_name="John" last_name="Doe" />
      <.user_avatar first_name="John" />
  """
  attr :first_name, :string, required: true
  attr :last_name, :string, default: nil
  attr :class, :string, default: nil

  def user_avatar(assigns) do
    initials =
      String.at(assigns.first_name, 0) <>
        if assigns.last_name, do: String.at(assigns.last_name, 0), else: ""

    assigns = assign(assigns, :initials, String.upcase(initials))

    ~H"""
    <div class={[
      "h-5 w-5 rounded-full bg-gray-100 flex items-center justify-center text-[10px] font-semibold text-gray-500",
      @class
    ]}>
      {@initials}
    </div>
    """
  end

  attr :current_user, Lightning.Accounts.User, required: true

  def user_menu_dropdown(assigns) do
    menu_id = "user-menu-#{:erlang.phash2(assigns.current_user.id)}"

    assigns =
      assigns
      |> assign(:menu_id, menu_id)
      |> assign(
        :custom_user_menu_items,
        Application.get_env(:lightning, :user_menu_items)
      )

    ~H"""
    <div
      id="user-menu-wrapper"
      class="h-10 mx-3 flex-1 relative"
      phx-click-away={JS.hide(to: "##{@menu_id}")}
      phx-window-keydown={JS.hide(to: "##{@menu_id}")}
      phx-key="Escape"
    >
      <button
        id="user-menu-trigger"
        class="user-menu-trigger menu-item menu-item-inactive h-10 w-full bg-white/10 hover:bg-white/20 rounded-lg text-sm font-medium flex items-center transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/30"
        phx-click={
          JS.toggle(
            to: "##{@menu_id}",
            in: "transition ease-out duration-100",
            out: "transition ease-in duration-75"
          )
        }
        type="button"
        aria-haspopup="true"
      >
        <div class="user-menu-content flex items-center">
          <.user_avatar
            first_name={@current_user.first_name}
            last_name={@current_user.last_name}
            class="shrink-0"
          />
          <div class="min-w-0 overflow-hidden flex-1 user-menu-text">
            <div class="text-sm font-medium text-white truncate">
              {@current_user.first_name}
              {if @current_user.last_name, do: " " <> @current_user.last_name}
            </div>
          </div>
          <.icon
            name="hero-chevron-down"
            class="w-4 h-4 text-white/70 shrink-0 user-menu-chevron"
          />
        </div>
      </button>
      <div
        id={@menu_id}
        class="hidden fixed z-9999 mt-2 w-56 origin-top-left divide-y divide-gray-100 rounded-md bg-white shadow-lg outline-1 outline-black/5"
        role="menu"
        aria-orientation="vertical"
      >
        <div class="px-4 py-3">
          <p class="text-sm text-gray-700">Signed in as</p>
          <p class="truncate text-sm font-medium text-gray-900">
            {@current_user.email}
          </p>
        </div>
        <%= if @custom_user_menu_items do %>
          {Phoenix.LiveView.TagEngine.component(
            @custom_user_menu_items.component,
            Map.take(assigns, @custom_user_menu_items.assigns_keys),
            {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
          )}
        <% else %>
          <div class="py-1">
            <.link
              navigate={~p"/projects"}
              class="flex items-center px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900"
              role="menuitem"
            >
              <Heroicons.folder class="h-5 w-5 inline-block mr-2" /> Projects
            </.link>
            <.link
              navigate={~p"/profile"}
              class="flex items-center px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900"
              role="menuitem"
            >
              <Heroicons.user_circle class="h-5 w-5 inline-block mr-2" />
              User Profile
            </.link>
            <.link
              navigate={~p"/credentials"}
              class="flex items-center px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900"
              role="menuitem"
            >
              <Heroicons.key class="h-5 w-5 inline-block mr-2" /> Credentials
            </.link>
            <.link
              navigate={~p"/profile/tokens"}
              class="flex items-center px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900"
              role="menuitem"
            >
              <Heroicons.command_line class="h-5 w-5 inline-block mr-2" /> API Tokens
            </.link>
          </div>
          <div class="py-1">
            <.link
              navigate={~p"/users/log_out"}
              class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900"
              role="menuitem"
            >
              Log out
            </.link>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def menu_items(assigns) do
    assigns =
      assigns
      |> assign(:custom_menu_items, Application.get_env(:lightning, :menu_items))

    ~H"""
    <%= if @custom_menu_items do %>
      {Phoenix.LiveView.TagEngine.component(
        @custom_menu_items.component,
        Map.take(assigns, @custom_menu_items.assigns_keys),
        {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
      )}
    <% else %>
      <%= if assigns[:project] do %>
        <Menu.project_items
          project_id={@project.id}
          current_user={@current_user}
          active_menu_item={@active_menu_item}
        />
      <% else %>
        <Menu.profile_items active_menu_item={@active_menu_item} />
      <% end %>
    <% end %>
    """
  end

  # https://play.tailwindcss.com/r7kBDT2cJY?layout=horizontal
  def page_content(assigns) do
    ~H"""
    <div class="flex h-full w-full flex-col">
      {if assigns[:banner], do: render_slot(@banner)}
      {if assigns[:header], do: render_slot(@header)}
      <div class="flex-auto bg-secondary-100 relative">
        <section
          id="inner_content"
          class="overflow-y-auto absolute top-0 bottom-0 left-0 right-0"
        >
          {render_slot(@inner_block)}
        </section>
      </div>
    </div>
    """
  end

  attr :current_user, Lightning.Accounts.User, default: nil
  attr :socket, Phoenix.LiveView.Socket
  attr :breadcrumbs, :list, default: []
  attr :project, :map, default: nil
  slot :title
  slot :period
  slot :description
  slot :inner_block

  defp collect_breadcrumbs(assigns) do
    # Add project name as first crumb if project is scoped
    project_crumb =
      if Map.get(assigns, :project) do
        [{assigns.project.name, "/projects/#{assigns.project.id}/w"}]
      else
        []
      end

    # Add manual breadcrumbs after project
    project_crumb ++ Map.get(assigns, :breadcrumbs, [])
  end

  def header(assigns) do
    # TODO - remove title_height once we confirm that :description is unused
    title_height =
      if assigns[:description] && assigns[:description] != [] do
        "mt-4 h-10"
      else
        "h-20"
      end

    breadcrumbs = collect_breadcrumbs(assigns)

    # description has the same title class except for height and font
    assigns =
      assign(assigns,
        title_class: "max-w-7xl mx-auto sm:px-6 lg:px-8",
        title_height: "py-6 flex items-center " <> title_height,
        breadcrumbs: breadcrumbs
      )

    ~H"""
    <LightningWeb.Components.Common.banner
      :if={
        Lightning.Config.check_flag?(:require_email_verification) &&
          assigns[:current_user] &&
          !@current_user.confirmed_at
      }
      id="account-confirmation-alert"
      type="danger"
      centered
      message={"Please confirm your account before #{@current_user.inserted_at |> DateTime.add(48, :hour) |> Timex.format!("%A, %d %B @ %H:%M UTC", :strftime)} to continue using OpenFn."}
      action={
        %{
          text: "Resend confirmation email",
          target: "/users/send-confirmation-email"
        }
      }
    />
    <div
      class="flex-none bg-white shadow-xs border-b border-gray-200"
      data-testid="top-bar"
    >
      <div class={[@title_class, @title_height]}>
        <%= if assigns[:current_user] do %>
          <%= if assigns[:project] do %>
            <nav class="flex" aria-label="Breadcrumb">
              <ol role="list" class="flex items-center space-x-2">
                <%!-- Show breadcrumbs --%>
                <%= for {{label, _path}, index} <- Enum.with_index(@breadcrumbs) do %>
                  <.breadcrumb_item label={label} index={index} />
                <% end %>

                <%!-- Page title --%>
                <.breadcrumb show_separator={length(@breadcrumbs) > 1}>
                  <:label>
                    {if assigns[:title], do: render_slot(@title)}
                  </:label>
                </.breadcrumb>
              </ol>
            </nav>
          <% else %>
            <h1 class="text-xl font-semibold text-secondary-900 flex items-center">
              {if assigns[:title], do: render_slot(@title)}
            </h1>
          <% end %>
        <% else %>
          <h1 class="text-3xl font-bold text-secondary-900 flex items-center">
            {if assigns[:title], do: render_slot(@title)}
          </h1>
        <% end %>
        <div class="grow"></div>
        {if assigns[:inner_block], do: render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :class, :string, default: ""
  slot :inner_block, required: true

  def centered(assigns) do
    ~H"""
    <div class={["max-w-7xl mx-auto py-6 sm:px-6 lg:px-8", @class]}>
      {render_slot(@inner_block)}
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

  attr :label, :string, required: true
  attr :index, :integer, required: true

  defp breadcrumb_item(%{index: 0} = assigns) do
    ~H"""
    <.breadcrumb_project_picker label={@label} />
    """
  end

  defp breadcrumb_item(assigns) do
    ~H"""
    <.breadcrumb show_separator={@index > 1}>
      <:label>{@label}</:label>
    </.breadcrumb>
    """
  end

  attr :label, :string, required: true
  attr :show_separator, :boolean, default: true

  def breadcrumb_project_picker(assigns) do
    ~H"""
    <li>
      <div class="flex items-center">
        <button
          id="breadcrumb-project-picker-trigger"
          type="button"
          phx-click={JS.dispatch("open-project-picker", to: "body")}
          class="flex items-center gap-2 px-2.5 py-1.5 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 hover:border-gray-400 cursor-pointer transition-colors"
        >
          <.icon name="hero-folder" class="h-4 w-4 text-gray-500" />
          {@label}
        </button>
      </div>
    </li>
    """
  end

  attr :path, :string, default: nil
  attr :show_separator, :boolean, default: true
  slot :label

  def breadcrumb(assigns) do
    ~H"""
    <li>
      <div class="flex items-center">
        <.icon
          :if={@show_separator}
          name="hero-chevron-right"
          class="h-5 w-5 shrink-0 text-gray-400"
        />
        <%= if @path do %>
          <.link
            patch={@path}
            class={[
              "flex text-sm font-medium text-gray-500 hover:text-gray-700",
              @show_separator && "ml-2"
            ]}
            aria-current="page"
          >
            {if assigns[:label], do: render_slot(@label)}
          </.link>
        <% else %>
          <span class={[
            "flex items-center text-sm font-medium text-gray-500",
            @show_separator && "ml-2"
          ]}>
            {if assigns[:label], do: render_slot(@label)}
          </span>
        <% end %>
      </div>
    </li>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :permissions_message, :string, required: true
  attr :can_perform_action, :boolean, default: true
  attr :action_button_text, :string, default: nil
  attr :action_button_click, :any, default: nil
  attr :action_button_value_action, :string, default: nil
  attr :action_button_target, :any, default: nil
  attr :action_button_disabled, :boolean, default: false
  attr :action_button_tooltip, :string, default: nil
  attr :action_button_id, :string, default: nil
  attr :options, :list, default: nil
  attr :role, :string, default: nil
  slot :action_button

  def section_header(assigns) do
    ~H"""
    <div class="flex justify-between content-center">
      <div>
        <h6 class="font-medium text-black">{@title}</h6>
        <small class="block my-1 text-xs text-gray-600">
          {@subtitle}
        </small>
        <%= if !@can_perform_action do %>
          <.permissions_message section={@permissions_message} />
        <% end %>
      </div>
      <%= if @action_button_text || @action_button != [] do %>
        <div class="sm:block" aria-hidden="true">
          <%= if @action_button != [] do %>
            {render_slot(@action_button)}
          <% else %>
            <.button
              :if={@action_button_id}
              id={@action_button_id}
              type="button"
              theme="primary"
              size="lg"
              phx-click={@action_button_click}
              phx-value-action={@action_button_value_action}
              phx-target={@action_button_target}
              disabled={@action_button_disabled}
              tooltip={@action_button_tooltip}
            >
              {@action_button_text}
            </.button>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :section, :string, required: true

  defp permissions_message(assigns) do
    ~H"""
    <small class="mt-2 text-red-700">
      Role based permissions: You cannot modify this project's {@section}
    </small>
    """
  end

  def sidebar_footer(assigns) do
    ~H"""
    <div class="flex-shrink-0 sidebar-footer flex flex-col border-t border-white/10 pt-3 mt-3">
      <%!-- Expanded branding: centered --%>
      <div class="sidebar-branding-expanded h-14 text-center">
        <div class="pt-2 pb-1">
          <LightningWeb.Components.Common.openfn_logo class="h-6 primary-light mx-auto" />
        </div>
        <div class="text-xs primary-light opacity-50">
          v{Application.spec(:lightning, :vsn)}
        </div>
      </div>
      <%!-- Collapsed branding: centered --%>
      <div class="sidebar-branding-collapsed hidden h-14 text-center">
        <div class="pt-2 pb-1">
          <LightningWeb.Components.Common.openfn_logo_collapsed class="h-6 primary-light mx-auto" />
        </div>
        <div class="text-xs primary-light opacity-50">
          v{Application.spec(:lightning, :vsn)}
        </div>
      </div>
      <div class="border-t border-white/10 mt-2">
        <button
          type="button"
          phx-click="toggle_sidebar"
          class="sidebar-toggle-btn w-full py-1.5 focus:outline-none cursor-pointer hover:bg-white/5 transition-colors"
          title="Toggle sidebar"
          aria-label="Toggle sidebar"
        >
          <div class="mx-3 flex items-center h-5 pl-3">
            <svg
              class="sidebar-collapse-icon w-5 h-5 text-white/70"
              viewBox="0 0 18 18"
              fill="currentColor"
              aria-hidden="true"
            >
              <path
                fill-rule="evenodd"
                d="M5.46 8.846l3.444-3.442-1.058-1.058-4.5 4.5 4.5 4.5 1.058-1.057L5.46 8.84zm7.194 4.5v-9h-1.5v9h1.5z"
              />
            </svg>
            <svg
              class="sidebar-expand-icon w-5 h-5 text-white/70 hidden"
              viewBox="0 0 18 18"
              fill="currentColor"
              aria-hidden="true"
            >
              <path
                fill-rule="evenodd"
                d="M12.54 9.154l-3.444 3.442 1.058 1.058 4.5-4.5-4.5-4.5-1.058 1.057 3.444 3.443zm-7.194-4.5v9h1.5v-9h-1.5z"
              />
            </svg>
          </div>
        </button>
      </div>
    </div>
    """
  end
end
