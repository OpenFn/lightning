defmodule LightningWeb.WorkflowHealthChannel do
  @moduledoc """
  Channel serving the workflow health page's aggregate stats.

  This channel is its own trust boundary — the health LiveView's `on_mount`
  guards do not protect it, since a client can join any topic over the socket.
  Access to the project is re-checked here on join, via the same policy the rest
  of the app uses — so support users get in and soft-deleted projects don't.
  """
  use LightningWeb, :channel

  alias Lightning.Policies.Permissions
  alias Lightning.Projects.Project
  alias Lightning.Workflows

  @impl true
  def join(
        "workflow_health:" <> workflow_id,
        %{"project_id" => project_id},
        socket
      ) do
    with %_{} = user <- socket.assigns[:current_user],
         {:ok, project_id} <- Ecto.UUID.cast(project_id),
         %{project: project} = workflow <-
           Workflows.get_workflow_for_project(
             %Project{id: project_id},
             workflow_id,
             include: [:project]
           ),
         :ok <- Permissions.can(:project_users, :access_project, user, project) do
      {:ok, assign(socket, :workflow, workflow)}
    else
      _ -> {:error, %{reason: "unauthorized"}}
    end
  end

  def join("workflow_health:" <> _workflow_id, _params, _socket) do
    {:error, %{reason: "invalid parameters. project_id is required"}}
  end

  # One handler per chart, so a cheap chart isn't held up by an expensive one.
  # Replies are still serialised — this is a GenServer — so the client should
  # request cheap slices first. If that ever bites, spawn a Task per request and
  # `push/3` the result instead of replying.
  @impl true
  def handle_in("get_outcomes", _params, socket) do
    {:reply, {:ok, Workflows.Stats.outcomes(socket.assigns.workflow)}, socket}
  end
end
