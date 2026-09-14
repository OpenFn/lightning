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

  defmodule ProjectDeletionScheduled do
    @moduledoc """
    The project was scheduled for deletion, so nobody may work in it any more.

    Project-wide rather than user-scoped, like `SupportAccessUpdated`:
    scheduling removes no membership row and revokes no token, so that refusal
    is the whole of the offboarding gate during the purge window and it applies
    to every actor in the project at once. Nothing a later change can do makes a
    wound-down project writable again, so sessions holding it end rather than
    being re-permissioned.

    The counterpart restore (`cancel_scheduled_deletion`) needs no event:
    sessions were ended, not degraded, and a rejoin resolves permissions fresh.
    """
    defstruct [:project_id]
  end

  defmodule WorkflowDeleted do
    @moduledoc """
    A workflow in the project was marked deleted.

    Soft deletion is what "deleted" means to everyone but the purge worker: the
    workflow disappears from the project, no join or mount resolves it again,
    and a session still holding it is holding something that is gone. Sessions
    end rather than being re-permissioned — nothing brings the workflow back
    under the same id.

    Carried here rather than on `Lightning.Workflows.Events` deliberately. That
    topic also carries `WorkflowUpdated`, which fires on every save in the
    project, so a surface subscribing there to hear about deletions would be
    woken by every keystroke's worth of saved work instead. The surfaces that
    need this already subscribe to the project's topic, and a deletion belongs
    with the other events that change what a session may do.
    """
    defstruct [:workflow_id, :project_id]
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

  def project_deletion_scheduled(project_id) do
    Lightning.broadcast(
      project_topic(project_id),
      %ProjectDeletionScheduled{project_id: project_id}
    )
  end

  def workflow_deleted(workflow) do
    Lightning.broadcast(
      project_topic(workflow.project_id),
      %WorkflowDeleted{
        workflow_id: workflow.id,
        project_id: workflow.project_id
      }
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
  `LightningWeb.Hooks.on_mount(:project_scope, ...)`, as do
  `LightningWeb.WorkflowChannel`, `LightningWeb.AiAssistantChannel` and
  `LightningWeb.RunChannel` at join. Anything broadcast on this topic reaches
  all of them, so new event types must be handled (or explicitly halted) in
  `LightningWeb.Hooks.handle_project_user_event/2` and named in each channel's
  ignore clause.

  Keep this topic quiet. It exists so that a session can be told its own
  standing changed, and every subscriber is woken for every message on it — a
  frequent event does not belong here.
  """
  def subscribe(project_id) do
    Lightning.subscribe(project_topic(project_id))
  end

  defp topic, do: "projects_events:all"

  defp project_topic(project_id), do: "project_events:#{project_id}"
end
