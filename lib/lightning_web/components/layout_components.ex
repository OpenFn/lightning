defmodule LightningWeb.LayoutComponents do
  @moduledoc false
  use LightningWeb, :html

  import PetalComponents.Avatar

  alias LightningWeb.Components.Menu

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
      class="relative w-full"
      phx-click-away={Phoenix.LiveView.JS.hide(to: "##{@menu_id}")}
      phx-window-keydown={Phoenix.LiveView.JS.hide(to: "##{@menu_id}")}
      phx-key="Escape"
    >
      <button
        class="w-full bg-white/10 hover:bg-white/20 rounded-lg px-3 py-2.5 text-left transition-colors focus:outline-none focus:ring-2 focus:ring-white/30 max-w-full"
        phx-click={
          Phoenix.LiveView.JS.toggle(
            to: "##{@menu_id}",
            in: "transition ease-out duration-100",
            out: "transition ease-in duration-75"
          )
        }
        type="button"
        aria-haspopup="true"
      >
        <div class="flex items-center gap-2 min-w-0">
          <div class="shrink-0">
            <.avatar
              size="sm"
              name={
                String.at(@current_user.first_name, 0) <>
                  if is_nil(@current_user.last_name),
                    do: "",
                    else: String.at(@current_user.last_name, 0)
              }
            />
          </div>
          <div class="min-w-0 overflow-hidden flex-1">
            <div class="text-sm font-medium text-white truncate">
              {@current_user.first_name}
              {if @current_user.last_name, do: " " <> @current_user.last_name}
            </div>
          </div>
          <.icon name="hero-chevron-down" class="w-4 h-4 text-white/70 shrink-0" />
        </div>
      </button>
      <div
        id={@menu_id}
        class="hidden absolute left-0 z-[9999] mt-2 w-56 origin-top-left divide-y divide-gray-100 rounded-md bg-white shadow-lg outline-1 outline-black/5"
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
      assign(assigns,
        custom_menu_items: Application.get_env(:lightning, :menu_items)
      )

    ~H"""
    <%= if @custom_menu_items do %>
      {Phoenix.LiveView.TagEngine.component(
        @custom_menu_items.component,
        Map.take(assigns, @custom_menu_items.assigns_keys),
        {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
      )}
    <% else %>
      <Common.combobox
        items={assigns[:projects] || []}
        selected_item={assigns[:project]}
        placeholder="Go to project"
        url_func={fn project -> ~p"/projects/#{project.id}/w" end}
      />
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
    # Add project breadcrumbs if project is scoped
    crumbs =
      if Map.get(assigns, :project) do
        base_crumbs = [
          {"Projects", "/projects"},
          {assigns.project.name, "/projects/#{assigns.project.id}/w"}
        ]

        if assigns.project.parent_id &&
             Ecto.assoc_loaded?(assigns.project.parent) do
          [
            {"Projects", "/projects"},
            {assigns.project.parent.name,
             "/projects/#{assigns.project.parent.id}/w"},
            {assigns.project.name, "/projects/#{assigns.project.id}/w"}
          ]
        else
          base_crumbs
        end
      else
        []
      end

    # Add manual breadcrumbs
    crumbs ++ Map.get(assigns, :breadcrumbs, [])
  end

  def header(assigns) do
    # TODO - remove title_height once we confirm that :description is unused
    title_height =
      if assigns[:description] && assigns[:description] != [] do
        "mt-4 h-10"
      else
        "h-20"
      end

    all_crumbs = collect_breadcrumbs(assigns)

    # We want max 2 items total (including the page title which is always shown)
    # So we can show at most 1 breadcrumb. If there are more, hide the earlier ones
    {hidden_crumbs, visible_crumbs} =
      if length(all_crumbs) > 1 do
        # Show only the last breadcrumb, hide all earlier ones
        {Enum.take(all_crumbs, length(all_crumbs) - 1),
         Enum.take(all_crumbs, -1)}
      else
        {[], all_crumbs}
      end

    # description has the same title class except for height and font
    assigns =
      assign(assigns,
        title_class: "max-w-7xl mx-auto sm:px-6 lg:px-8",
        title_height: "py-6 flex items-center " <> title_height,
        hidden_crumbs: hidden_crumbs,
        visible_crumbs: visible_crumbs
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
          <nav class="flex" aria-label="Breadcrumb">
            <ol role="list" class="flex items-center space-x-2">
              <%!-- Show ellipsis dropdown if there are hidden breadcrumbs --%>
              <%= if @hidden_crumbs != [] do %>
                <.breadcrumb_dropdown items={@hidden_crumbs} />
              <% end %>

              <%!-- Show visible breadcrumbs --%>
              <%= for {{label, path}, index} <- Enum.with_index(@visible_crumbs) do %>
                <.breadcrumb
                  path={path}
                  show_separator={(@hidden_crumbs != [] and index == 0) or index > 0}
                >
                  <:label>{label}</:label>
                </.breadcrumb>
              <% end %>

              <%!-- And finally, we always show the page title --%>
              <.breadcrumb show_separator={
                @hidden_crumbs != [] or @visible_crumbs != []
              }>
                <:label>
                  {if assigns[:title], do: render_slot(@title)}
                </:label>
              </.breadcrumb>
            </ol>
          </nav>
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

  attr :items, :list, required: true

  def breadcrumb_dropdown(assigns) do
    dropdown_id = "breadcrumb-dropdown-#{:erlang.phash2(assigns.items)}"
    assigns = assign(assigns, :dropdown_id, dropdown_id)

    ~H"""
    <li>
      <div class="flex items-center">
        <div
          class="relative"
          phx-click-away={Phoenix.LiveView.JS.hide(to: "##{@dropdown_id}")}
          phx-window-keydown={Phoenix.LiveView.JS.hide(to: "##{@dropdown_id}")}
          phx-key="Escape"
        >
          <button
            class="flex items-center text-sm font-medium text-gray-500 hover:text-gray-700"
            phx-click={
              Phoenix.LiveView.JS.toggle(
                to: "##{@dropdown_id}",
                in: "transition ease-out duration-100",
                out: "transition ease-in duration-75"
              )
            }
            type="button"
            aria-haspopup="true"
          >
            <.icon name="hero-ellipsis-horizontal" class="h-5 w-5" />
          </button>
          <div
            id={@dropdown_id}
            class="hidden absolute left-0 z-[9999] mt-2 w-48 origin-top-left rounded-md bg-white shadow-lg outline-1 outline-black/5"
            role="menu"
          >
            <div class="py-1">
              <%= for {label, path} <- @items do %>
                <.link
                  patch={path}
                  class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
                  role="menuitem"
                >
                  {label}
                </.link>
              <% end %>
            </div>
          </div>
        </div>
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
        <%= if @show_separator do %>
          <svg
            class="h-5 w-5 shrink-0 text-gray-400"
            viewBox="0 0 20 20"
            fill="currentColor"
            aria-hidden="true"
          >
            <path
              fill-rule="evenodd"
              d="M7.21 14.77a.75.75 0 01.02-1.06L11.168 10 7.23 6.29a.75.75 0 111.04-1.08l4.5 4.25a.75.75 0 010 1.08l-4.5 4.25a.75.75 0 01-1.06-.02z"
              clip-rule="evenodd"
            />
          </svg>
        <% end %>
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
end
