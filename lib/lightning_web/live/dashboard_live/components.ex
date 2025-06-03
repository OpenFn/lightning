defmodule LightningWeb.DashboardLive.Components do
  use LightningWeb, :component

  alias LightningWeb.Components.Common
  alias Phoenix.LiveView.JS

  def welcome_banner(assigns) do
    ~H"""
    <div class="mb-2 min-h-[100px]"
         phx-hook="TypewriterHook"
         id="welcome-banner-typewriter"
         data-user-name={@user.first_name}
         data-p-html={~s|Click on a project to get started. If you need some help, head to <a href="https://docs.openfn.org" target="_blank" class="link">docs.openfn.org</a> or <a href="https://community.openfn.org" target="_blank" class="link">community.openfn.org</a> to learn more.|}>
      <div class="flex justify-between items-center pt-6">
        <h1 class="text-2xl font-medium">
          <span id="typewriter-h1"></span><span id="cursor-h1" class="typewriter-cursor"></span>
        </h1>
      </div>

      <div id="welcome-banner-content">
        <p class="mb-6 mt-4">
          <span id="typewriter-p"></span><span id="cursor-p" class="typewriter-cursor" style="display: none;"></span>
        </p>
      </div>

      <style>
        .typewriter-cursor::after {
          content: '|';
          animation: blink 1s infinite;
          color: #666;
        }

        @keyframes blink {
          0%, 50% { opacity: 1; }
          51%, 100% { opacity: 0; }
        }
      </style>
    </div>
    """
  end

  defp table_title(assigns) do
    ~H"""
    <h3 class="text-3xl font-bold">
      Projects
      <span class="text-base font-normal">
        ({@count})
      </span>
    </h3>
    """
  end

  def user_projects_table(assigns) do
    assigns =
      assign(assigns,
        projects_count: assigns.projects |> Enum.count(),
        empty?: assigns.projects |> Enum.empty?()
      )

    ~H"""
    <%= if @empty? do %>
      {render_slot(@empty_state)}
    <% else %>
      <div class="mt-5 flex justify-between mb-3">
        <.table_title count={@projects_count} />
        <div>
          {render_slot(@create_project_button)}
        </div>
      </div>
      <div>
        <.table id="projects-table">
          <:header>
            <.tr>
              <.th
                sortable={true}
                sort_by="name"
                active={@sort_key == "name"}
                sort_direction={@sort_direction}
                phx_target={@target}
              >
                Name
              </.th>
              <.th>Role</.th>
              <.th>Workflows</.th>
              <.th>Collaborators</.th>
              <.th
                sortable={true}
                sort_by="last_updated_at"
                active={@sort_key == "last_updated_at"}
                sort_direction={@sort_direction}
                phx_target={@target}
              >
                Last Updated
              </.th>
              <.th></.th>
            </.tr>
          </:header>
          <:body>
            <%= for project <- @projects do %>
              <.tr
                id={"projects-table-row-#{project.id}"}
                class="hover:bg-gray-100 transition-colors duration-200"
                onclick={JS.navigate(~p"/projects/#{project.id}/w")}
              >
                <.td>
                  {project.name}
                </.td>
                <.td class="break-words max-w-[25rem]">
                  {String.capitalize(to_string(project.role))}
                </.td>
                <.td class="break-words max-w-[10rem]">
                  {project.workflows_count}
                </.td>
                <.td class="break-words max-w-[5rem]">
                  <.link
                    class="link"
                    href={~p"/projects/#{project.id}/settings#collaboration"}
                    onclick="event.stopPropagation()"
                  >
                    {project.collaborators_count}
                  </.link>
                </.td>
                <.td>
                  <%= if project.last_updated_at do %>
                    {Lightning.Helpers.format_date(project.last_updated_at)}
                  <% else %>
                    N/A
                  <% end %>
                </.td>
                <.td class="text-right">
                  <.link
                    class="table-action"
                    navigate={~p"/projects/#{project.id}/history"}
                    onclick="event.stopPropagation()"
                  >
                    History
                  </.link>
                </.td>
              </.tr>
            <% end %>
          </:body>
        </.table>
      </div>
    <% end %>
    """
  end

  attr :current_sort_key, :string, required: true
  attr :current_sort_direction, :string, required: true
  attr :target, :any, required: true
  attr :target_sort_key, :string, required: true
  slot :inner_block, required: true

  defp sortable_table_header(assigns) do
    ~H"""
    <Common.sortable_table_header
      phx-click="sort"
      phx-value-by={@target_sort_key}
      phx-target={@target}
      active={@current_sort_key == @target_sort_key}
      sort_direction={@current_sort_direction}
    >
      {render_slot(@inner_block)}
    </Common.sortable_table_header>
    """
  end
end
