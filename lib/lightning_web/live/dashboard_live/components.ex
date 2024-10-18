defmodule LightningWeb.DashboardLive.Components do
  use LightningWeb, :component

  import PetalComponents.Table

  # alias Lightning.Accounts.User
  # alias Lightning.Projects.Project

  defp table_title(assigns) do
    ~H"""
    <h3 class="text-3xl font-bold">
      Projects
      <span class="text-base font-normal">
        (<%= @count %>)
      </span>
    </h3>
    """
  end

  def user_projects_table(assigns) do
    next_sort_icon = %{asc: "hero-chevron-down", desc: "hero-chevron-up"}

    assigns =
      assign(assigns,
        projects_count: assigns.projects |> Enum.count(),
        empty?: assigns.projects |> Enum.empty?(),
        name_sort_icon: next_sort_icon[assigns.name_direction],
        activity_sort_icon: next_sort_icon[assigns.activity_direction]
      )

    ~H"""
    <%= if @empty? do %>
      <%= render_slot(@empty_state) %>
    <% else %>
      <div class="mt-5 flex justify-between mb-3">
        <.table_title count={@projects_count} />
        <div>
          <%= render_slot(@create_project_button) %>
        </div>
      </div>
      <.table id="projects-table">
        <.tr>
          <.th>
            <div class="group inline-flex items-center">
              Name
              <span
                phx-click="sort"
                phx-value-by="name"
                class="cursor-pointer align-middle ml-2 flex-none rounded text-gray-400 group-hover:visible group-focus:visible"
              >
                <.icon name={@name_sort_icon} />
              </span>
            </div>
          </.th>
          <.th>Role</.th>
          <.th>Workflows</.th>
          <.th>Collaborators</.th>
          <.th>
            <div class="group inline-flex items-center">
              Last Activity
              <span
                phx-click="sort"
                phx-value-by="activity"
                class="cursor-pointer align-middle ml-2 flex-none rounded text-gray-400 group-hover:visible group-focus:visible"
              >
                <.icon name={@activity_sort_icon} />
              </span>
            </div>
          </.th>
          <.th></.th>
        </.tr>

        <.tr
          :for={project <- @projects}
          id={"projects-table-row-#{project.id}"}
          class="hover:bg-gray-100 transition-colors duration-200"
        >
          <.td>
            <.link
              class="break-words max-w-[15rem] text-gray-800"
              href={~p"/projects/#{project.id}/w"}
            >
              <%= project.name %>
            </.link>
          </.td>
          <.td class="break-words max-w-[25rem]">
            <%= project.role
            |> Atom.to_string()
            |> String.capitalize() %>
          </.td>
          <.td class="break-words max-w-[10rem]">
            <%= project.workflows_count %>
          </.td>
          <.td class="break-words max-w-[5rem]">
            <.link
              class="link"
              href={~p"/projects/#{project.id}/settings#collaboration"}
            >
              <%= project.collaborators_count %>
            </.link>
          </.td>
          <.td>
            <%= if project.last_activity do %>
              <%= Lightning.Helpers.format_date(
                project.last_activity,
                "%d/%m/%Y at %H:%M:%S"
              ) %>
            <% else %>
              No activity
            <% end %>
          </.td>
          <.td class="text-right">
            <.link
              class="table-action"
              navigate={~p"/projects/#{project.id}/history"}
            >
              History
            </.link>
          </.td>
        </.tr>
      </.table>
    <% end %>
    """
  end
end
