defmodule LightningWeb.ProjectLive.Index do
  @moduledoc """
  The projects admin page: every project on the instance, the form that
  creates or changes one (`/new`, `/:id`), and the deletion dialog
  (`/:id/delete`). One LiveView; the page shows what the route opened.
  """
  use LightningWeb, :live_view

  on_mount {LightningWeb.Hooks, :ensure_admin}

  alias Lightning.Accounts
  alias Lightning.Helpers
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users
  alias Lightning.Projects
  alias Lightning.Projects.Project

  @roles ~w(owner admin editor viewer)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       active_menu_item: :projects,
       grace_period_days: Lightning.Config.purge_deleted_after_days() || 0,
       projects: [],
       form_project: nil,
       form_users: [],
       delete_project: nil
     ), layout: {LightningWeb.Layouts, :settings}}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  # The page sorts and filters in the browser; the list arrives by name.
  defp apply_action(socket, :index, _params) do
    assign(socket,
      page_title: "Projects",
      projects: Projects.list_projects_with_users(),
      form_project: nil,
      form_users: [],
      delete_project: nil
    )
  end

  # An unknown id raises here, as it always has (a 404).
  defp apply_action(socket, :edit, %{"id" => id}) do
    assign(socket,
      page_title: "Edit Project",
      projects: [],
      form_project: Projects.get_project_with_users!(id),
      form_users: form_users(),
      delete_project: nil
    )
  end

  defp apply_action(socket, :new, _params) do
    assign(socket,
      page_title: "New Project",
      projects: [],
      form_project: %Project{project_users: []},
      form_users: form_users(),
      delete_project: nil
    )
  end

  # The dialog's project is the route's; the page never says which to delete.
  defp apply_action(socket, :delete, %{"id" => id}) do
    case fetch_project(id) do
      {:ok, project} ->
        assign(socket,
          page_title: "Projects",
          projects: Projects.list_projects_with_users(),
          form_project: nil,
          form_users: [],
          delete_project: project
        )

      :error ->
        socket
        |> put_flash(:error, "Project not found")
        |> push_patch(to: ~p"/settings/projects")
    end
  end

  # Every account, in the order the old form built its rows.
  defp form_users, do: Enum.sort_by(Accounts.list_users(), & &1.first_name)

  @impl true
  def handle_event("cancel_deletion", params, socket) when is_map(params) do
    with :ok <- authorize(socket),
         {:ok, project} <- fetch_project(socket, params["id"]),
         :ok <- scheduled?(socket, project) do
      case Projects.cancel_scheduled_deletion(project.id) do
        {:ok, _project} ->
          {:reply, %{},
           socket
           |> put_flash(:info, "Project deletion canceled")
           |> push_patch(to: ~p"/settings/projects")}

        {:error, _changeset} ->
          reply_error(socket, "Cancel project deletion failed")
      end
    end
  end

  # The dialog's one action: schedule the project for deletion, or purge
  # one already scheduled. The project is the route's, read again now; the
  # dialog said which of the two it was, so a project scheduled by someone
  # else meanwhile is refused rather than purged. The typed name is checked
  # against the project's own name, never one from the payload.
  def handle_event("delete_project", params, socket) when is_map(params) do
    with :ok <- authorize(socket),
         {:ok, opened} <- open_for_deletion(socket),
         {:ok, project} <- fetch_project(socket, opened.id),
         :ok <- same_action?(socket, opened, project) do
      typed =
        if is_binary(params["nameConfirmation"]),
          do: params["nameConfirmation"],
          else: ""

      changeset =
        Projects.validate_for_deletion(project, %{
          "name" => project.name,
          "name_confirmation" => typed
        })

      if changeset.valid?,
        do: delete(socket, project),
        else: reply_error(socket, "doesn't match the project name")
    end
  end

  # The open form's Save. Which project is saved is the route's to know;
  # the payload carries the name as typed and a role per user id.
  def handle_event("save_project", params, socket) when is_map(params) do
    with :ok <- authorize(socket),
         {:ok, project} <- open_form(socket),
         {:ok, attrs} <- project_params(socket, params) do
      save(socket, socket.assigns.live_action, project, attrs)
    end
  end

  def handle_event(event, _params, socket)
      when event in ["cancel_deletion", "delete_project", "save_project"],
      do: reply_error(socket, "Invalid request")

  # The mount gate is :ensure_admin; every event checks the same policy again.
  defp authorize(socket) do
    if Permissions.can?(
         Users,
         :access_admin_space,
         socket.assigns.current_user,
         {}
       ),
       do: :ok,
       else:
         reply_error(socket, "You are not authorized to perform this action.")
  end

  # An id from the route or a payload may be anything; only a UUID of an
  # existing project passes.
  defp fetch_project(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Project{} = project <- Projects.get_project(uuid) do
      {:ok, project}
    else
      _ -> :error
    end
  end

  defp fetch_project(socket, id) do
    case fetch_project(id) do
      {:ok, project} -> {:ok, project}
      :error -> reply_error(socket, "Project not found")
    end
  end

  defp open_for_deletion(%{
         assigns: %{live_action: :delete, delete_project: %Project{} = project}
       }),
       do: {:ok, project}

  defp open_for_deletion(socket), do: reply_error(socket, "Project not found")

  defp open_form(%{
         assigns: %{live_action: action, form_project: %Project{} = project}
       })
       when action in [:new, :edit],
       do: {:ok, project}

  defp open_form(socket), do: reply_error(socket, "Project not found")

  # The menu offers "Cancel deletion" on scheduled projects only.
  defp scheduled?(_socket, %Project{scheduled_deletion: %DateTime{}}), do: :ok
  defp scheduled?(socket, _project), do: reply_error(socket, "Invalid request")

  defp same_action?(socket, opened, project) do
    if is_nil(opened.scheduled_deletion) == is_nil(project.scheduled_deletion),
      do: :ok,
      else:
        reply_error(
          socket,
          "This project's deletion changed since the dialog opened. Reload the page."
        )
  end

  defp delete(socket, %Project{scheduled_deletion: nil} = project) do
    case Projects.schedule_project_deletion(project) do
      {:ok, %Project{}} ->
        {:reply, %{},
         socket
         |> put_flash(:info, "Project scheduled for deletion")
         |> push_navigate(to: ~p"/settings/projects")}

      {:error, %Ecto.Changeset{} = changeset} ->
        reply_error(socket, changeset)
    end
  end

  defp delete(socket, project) do
    {:ok, %Oban.Job{}} = Projects.delete_project_async(project)

    {:reply, %{},
     socket
     |> put_flash(
       :info,
       "Project deletion started. This may take a while to complete."
     )
     |> push_navigate(to: ~p"/settings/projects")}
  end

  defp save(socket, :new, _project, params) do
    params |> Projects.create_project() |> saved(socket, "created")
  end

  defp save(socket, :edit, project, params) do
    project
    |> Projects.update_project_with_users(params, socket.assigns.current_user)
    |> saved(socket, "updated")
  end

  defp saved({:ok, _project}, socket, verb) do
    {:reply, %{},
     socket
     |> put_flash(:info, "Project #{verb} successfully")
     |> push_patch(to: ~p"/settings/projects")}
  end

  defp saved({:error, %Ecto.Changeset{} = changeset}, socket, _verb) do
    # The form shows the name's error on its Name field (D29 precedent).
    changeset = Helpers.copy_error(changeset, :name, :raw_name)

    reply_error(socket, %{
      changeset
      | errors: Keyword.delete(changeset.errors, :name)
    })
  end

  # The page's values as the changeset's params, the way the old form built
  # them: one row per user the form listed; an existing member keeps its id
  # (role "" marks it for deletion, no entry leaves it as it is), a
  # non-member with no role is left out. Only the users the form listed and
  # only known roles count, so a crafted payload can't add anyone else, set
  # another field, or remove a member by sending nonsense for them. The old
  # owner's row goes first, so handing a project over in one save does not
  # trip the one-owner index on the way.
  defp project_params(socket, params) do
    %{form_project: project, form_users: users} = socket.assigns
    raw_name = if is_binary(params["rawName"]), do: params["rawName"], else: ""
    roles = if is_map(params["roles"]), do: params["roles"], else: %{}

    if Enum.all?(roles, fn {_id, role} -> role in ([""] ++ @roles) end) do
      rows =
        users
        |> Enum.flat_map(&member_row(project, &1, roles))
        |> Enum.sort_by(&demotion_first/1)
        |> Enum.with_index(fn {_existing, row}, index ->
          {to_string(index), row}
        end)

      {:ok,
       %{
         "raw_name" => raw_name,
         "project_users" => Map.new(rows),
         "users_sort" => Enum.map(rows, &elem(&1, 0))
       }
       |> Helpers.derive_name_param()}
    else
      reply_error(socket, "Invalid request")
    end
  end

  defp member_row(project, user, roles) do
    existing = Enum.find(project.project_users, &(&1.user_id == user.id))
    current = (existing && to_string(existing.role)) || ""
    role = Map.get(roles, user.id, current)

    cond do
      existing && role == "" ->
        [
          {existing,
           %{
             "id" => existing.id,
             "user_id" => user.id,
             "role" => "",
             "delete" => "true"
           }}
        ]

      existing ->
        [
          {existing,
           %{"id" => existing.id, "user_id" => user.id, "role" => role}}
        ]

      role == "" ->
        []

      true ->
        [{nil, %{"user_id" => user.id, "role" => role}}]
    end
  end

  defp demotion_first({%{role: :owner}, %{"role" => role}}) when role != "owner",
    do: 0

  defp demotion_first(_row), do: 1

  def get_project_owner_name(project) do
    case Enum.find(project.project_users, fn pu -> pu.role == :owner end) do
      %{user: user} when not is_nil(user) ->
        String.trim("#{user.first_name} #{user.last_name}")

      _ ->
        ""
    end
  end

  # --- Props ---

  # The shape the design system's AdminProjectRow type expects.
  defp projects_json(projects) do
    Enum.map(projects, fn project ->
      %{
        id: project.id,
        name: project.name,
        # The old sort and filter read a missing description as "".
        description: project.description || "",
        insertedAt: utc(project.inserted_at),
        ownerName: get_project_owner_name(project),
        scheduledDeletion: project.scheduled_deletion
      }
    end)
  end

  # The design system's AdminProjectForm while the route has the form open.
  defp form_json(nil, _users), do: nil

  defp form_json(%Project{id: nil}, users),
    do: %{project: nil, users: users_json(users)}

  defp form_json(%Project{} = project, users) do
    %{
      project: %{
        id: project.id,
        name: project.name,
        members:
          Enum.map(project.project_users, &%{userId: &1.user_id, role: &1.role})
      },
      users: users_json(users)
    }
  end

  defp users_json(users) do
    Enum.map(
      users,
      &%{
        id: &1.id,
        firstName: &1.first_name,
        lastName: &1.last_name,
        email: &1.email
      }
    )
  end

  defp delete_project_json(nil), do: nil

  # The dialog shows the name; whether it schedules or purges is the server's.
  defp delete_project_json(%Project{} = project),
    do: %{id: project.id, name: project.name}

  # `inserted_at` is naive; the page reads times as UTC, so say so.
  defp utc(%NaiveDateTime{} = naive), do: DateTime.from_naive!(naive, "Etc/UTC")
  defp utc(other), do: other
end
