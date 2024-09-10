defmodule LightningWeb.LayoutComponents do
  @moduledoc false
  use LightningWeb, :html

  import PetalComponents.Dropdown
  import PetalComponents.Avatar

  alias LightningWeb.Components.Menu

  def menu_items(assigns) do
    assigns =
      assign(assigns,
        custom_menu_items: Application.get_env(:lightning, :menu_items)
      )

    ~H"""
    <%= if @custom_menu_items do %>
      <%= Phoenix.LiveView.TagEngine.component(
        @custom_menu_items.component,
        Map.take(assigns, @custom_menu_items.assigns_keys),
        {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
      ) %>
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

  attr :current_user, Lightning.Accounts.User, default: nil
  attr :socket, Phoenix.LiveView.Socket
  attr :breadcrumbs, :list, default: []
  attr :project, :map, default: nil
  slot :title
  slot :period
  slot :description
  slot :inner_block

  def header(assigns) do
    # TODO - remove title_height once we confirm that :description is unused
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
    <LightningWeb.Components.Common.banner
      :if={@current_user && !@current_user.confirmed_at}
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
    <div class="flex-none bg-white shadow-sm">
      <div class={[@title_class, @title_height]}>
        <%= if @current_user do %>
          <nav class="flex" aria-label="Breadcrumb">
            <ol role="list" class="flex items-center space-x-4">
              <li>
                <div>
                  <a href="/" class="text-gray-400 hover:text-gray-500">
                    <svg
                      class="h-5 w-5 flex-shrink-0"
                      viewBox="0 0 20 20"
                      fill="currentColor"
                      aria-hidden="true"
                    >
                      <path
                        fill-rule="evenodd"
                        d="M9.293 2.293a1 1 0 011.414 0l7 7A1 1 0 0117 11h-1v6a1 1 0 01-1 1h-2a1 1 0 01-1-1v-3a1 1 0 00-1-1H9a1 1 0 00-1 1v3a1 1 0 01-1 1H5a1 1 0 01-1-1v-6H3a1 1 0 01-.707-1.707l7-7z"
                        clip-rule="evenodd"
                      />
                    </svg>
                    <span class="sr-only">Home</span>
                  </a>
                </div>
              </li>

              <%!-- If a project is scoped, we automatically generate the base crumbs --%>
              <%= if @project do %>
                <.breadcrumb path="/projects">
                  <:label>Projects</:label>
                </.breadcrumb>
                <.breadcrumb path={"/projects/#{@project.id}/w"}>
                  <:label><%= @project.name %></:label>
                </.breadcrumb>
              <% end %>

              <%!-- If breamcrumbs are passed manually, we generate those --%>
              <%= for {label, path} <- @breadcrumbs do %>
                <.breadcrumb path={path}>
                  <:label><%= label %></:label>
                </.breadcrumb>
              <% end %>

              <%!-- And finally, we always show the page title --%>
              <.breadcrumb>
                <:label>
                  <%= if assigns[:title], do: render_slot(@title) %>
                </:label>
              </.breadcrumb>
            </ol>
          </nav>
        <% else %>
          <h1 class="text-3xl font-bold text-secondary-900 flex items-center">
            <%= if assigns[:title], do: render_slot(@title) %>
          </h1>
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
                <.icon
                  name="hero-chevron-down"
                  class="w-4 h-4 ml-1 -mr-1 text-secondary-400 dark:text-secondary-100"
                />
              </div>
            </:trigger_element>
            <.dropdown_menu_item link_type="live_redirect" to={~p"/profile"}>
              <.icon name="hero-user-circle" class="w-5 h-5 text-secondary-500" />
              User Profile
            </.dropdown_menu_item>
            <.dropdown_menu_item link_type="live_redirect" to={~p"/credentials"}>
              <.icon name="hero-key" class="w-5 h-5 text-secondary-500" />
              Credentials
            </.dropdown_menu_item>
            <.dropdown_menu_item link_type="live_redirect" to={~p"/profile/tokens"}>
              <.icon name="hero-command-line" class="w-5 h-5 text-secondary-500" />
              API Tokens
            </.dropdown_menu_item>
            <.dropdown_menu_item link_type="live_redirect" to={~p"/users/log_out"}>
              <.icon
                name="hero-arrow-right-on-rectangle"
                class="w-5 h-5 text-secondary-500"
              /> Log out
            </.dropdown_menu_item>
          </.dropdown>
        <% end %>
      </div>
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

  attr :path, :string, default: nil
  slot :label

  def breadcrumb(assigns) do
    ~H"""
    <li>
      <div class="flex items-center">
        <svg
          class="h-5 w-5 flex-shrink-0 text-gray-400"
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
        <%= if @path do %>
          <.link
            patch={@path}
            class="flex ml-4 text-sm font-medium text-gray-500 hover:text-gray-700"
            aria-current="page"
          >
            <%= if assigns[:label], do: render_slot(@label) %>
          </.link>
        <% else %>
          <span class="flex ml-4 text-sm font-medium text-gray-500">
            <%= if assigns[:label], do: render_slot(@label) %>
          </span>
        <% end %>
      </div>
    </li>
    """
  end
end
