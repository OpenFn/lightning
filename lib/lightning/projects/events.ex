defmodule Lightning.Projects.Events do
  @moduledoc """
  Events for Projects changes.
  """
  defmodule ProjectCreated do
    @moduledoc false
    defstruct project: nil
  end

  defmodule ProjectDeleted do
    @moduledoc false
    defstruct project: nil
  end

  defmodule ProjectUserAdded do
    @moduledoc """
    A user was granted membership of a project.
    """
    defstruct [:project_id, :user_id]
  end

  defmodule ProjectUserRemoved do
    @moduledoc """
    A user's membership of a project was revoked.
    """
    defstruct [:project_id, :user_id]
  end

  defmodule ProjectUserRoleChanged do
    @moduledoc """
    A member's role on a project changed, so their permissions did too.
    """
    defstruct [:project_id, :user_id]
  end

  defmodule SupportAccessUpdated do
    @moduledoc """
    The project's allow_support_access flag changed, so every support user's
    standing on the project did too.
    """
    defstruct [:project_id, :allowed]
  end

  def project_created(project) do
    Lightning.broadcast(
      topic(),
      %ProjectCreated{project: project}
    )
  end

  def project_deleted(project) do
    Lightning.broadcast(
      topic(),
      %ProjectDeleted{project: project}
    )
  end

  def project_user_added(project_id, user_id) do
    Lightning.broadcast(
      project_topic(project_id),
      %ProjectUserAdded{project_id: project_id, user_id: user_id}
    )
  end

  def project_user_removed(project_id, user_id) do
    Lightning.broadcast(
      project_topic(project_id),
      %ProjectUserRemoved{project_id: project_id, user_id: user_id}
    )
  end

  def project_user_role_changed(project_id, user_id) do
    Lightning.broadcast(
      project_topic(project_id),
      %ProjectUserRoleChanged{project_id: project_id, user_id: user_id}
    )
  end

  def support_access_updated(project_id, allowed) do
    Lightning.broadcast(
      project_topic(project_id),
      %SupportAccessUpdated{project_id: project_id, allowed: allowed}
    )
  end

  def subscribe do
    Lightning.subscribe(topic())
  end

  @doc """
  Subscribes to events scoped to a single project.

  Note that every project-scoped LiveView subscribes here via
  `LightningWeb.Hooks.on_mount(:project_scope, ...)`. Anything broadcast on this
  topic reaches all of them, so new event types must be handled (or explicitly
  halted) in `LightningWeb.Hooks.handle_project_user_event/2`.
  """
  def subscribe(project_id) do
    Lightning.subscribe(project_topic(project_id))
  end

  defp topic, do: "projects_events:all"

  defp project_topic(project_id), do: "project_events:#{project_id}"
end
