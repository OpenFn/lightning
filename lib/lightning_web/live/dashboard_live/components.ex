defmodule LightningWeb.DashboardLive.Components do
  use LightningWeb, :component

  alias Lightning.Projects.Project
  alias Lightning.Accounts.User

  defp project_role(
         %User{id: user_id} = _user,
         %Project{project_users: project_users} = _project
       ) do
    project_users
    |> Enum.find(fn pu -> pu.user_id == user_id end)
    |> Map.get(:role)
    |> Atom.to_string()
    |> String.capitalize()
  end

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
    assigns =
      assign(assigns,
        projects_count: assigns.projects |> Enum.count(),
        empty?: assigns.projects |> Enum.empty?()
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
          <.th>Name</.th>
          <.th>Role</.th>
          <.th>Workflows</.th>
          <.th>Collaborators</.th>
          <.th>Last Activity</.th>
        </.tr>

        <.tr
          :for={project <- @projects}
          id={"projects-table-row-#{project.id}"}
          class="hover:bg-gray-100 transition-colors duration-200"
        >
          <.td class="break-words max-w-[15rem] flex items-center">
            <.link class="text-gray-800" href={~p"/projects/#{project.id}/w"}>
              <%= project.name %>
            </.link>
          </.td>
          <.td class="break-words max-w-[25rem]">
            <%= project_role(@user, project) %>
          </.td>
          <.td class="break-words max-w-[10rem]">
            <%= length(project.workflows) %>
          </.td>
          <.td class="break-words max-w-[5rem]">
            <.link
              class="text-primary-700"
              href={~p"/projects/#{project.id}/settings#collaboration"}
            >
              <%= length(project.project_users) %>
            </.link>
          </.td>
          <.td>
            <.link class="text-gray-800" href={~p"/projects/#{project.id}/history"}>
              <%= Lightning.Helpers.format_date(
                project.updated_at,
                "%d/%b/%Y %H:%M:%S"
              ) %>
            </.link>
          </.td>
        </.tr>
      </.table>
    <% end %>
    """
  end
end
