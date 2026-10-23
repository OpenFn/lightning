defmodule LightningWeb.DashboardLive.Index do
  use LightningWeb, :live_view

  alias Lightning.Helpers
  alias Lightning.Projects

  require Logger

  on_mount {LightningWeb.Hooks, :project_scope}
  on_mount {LightningWeb.Hooks, :assign_projects}
  on_mount {LightningWeb.Hooks, :check_limits}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Projects", active_menu_item: :projects)
     |> assign_projects()}
  end

  # Self-service create only sets the name/description the form exposes; a
  # crafted payload must not mass-assign privileged fields (notably parent_id,
  # which would attach the new project under an arbitrary parent, bypassing
  # gated sandbox provisioning) or inject arbitrary project_users.
  @impl true
  def handle_event("create_project", params, socket) do
    current_user = socket.assigns.current_user

    %{
      "raw_name" => Map.get(params, "rawName"),
      "description" => Map.get(params, "description")
    }
    |> Helpers.derive_name_param()
    |> Map.put("project_users", %{
      0 => %{"user_id" => current_user.id, "role" => "owner"}
    })
    |> Projects.create_project(false)
    |> case do
      {:ok, _project} ->
        {:reply, %{},
         socket
         |> put_flash(:info, "Project created successfully")
         |> assign_projects()}

      {:error, %Ecto.Changeset{} = changeset} ->
        # The form shows the name's error on its Name field only.
        changeset = Helpers.copy_error(changeset, :name, :raw_name)
        errors = Keyword.delete(changeset.errors, :name)
        reply_error(socket, %{changeset | errors: errors})
    end
  end

  # Sorting moved to the browser, so a "sort" (or any other) event from an
  # old or crafted client is ignored instead of crashing the page.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # Sorted by name; the page sorts the other way round in the browser.
  defp assign_projects(socket) do
    assign(
      socket,
      :projects,
      Projects.get_projects_overview(socket.assigns.current_user)
    )
  end

  # The shape the design system's ProjectOverview type expects.
  defp projects_json(projects) do
    Enum.map(projects, fn project ->
      %{
        id: project.id,
        name: project.name,
        role: to_string(project.role),
        workflowsCount: project.workflows_count,
        collaboratorsCount: project.collaborators_count,
        lastUpdatedAt: project.last_updated_at
      }
    end)
  end
end
