defmodule LightningWeb.WorkflowNewLive do
  @moduledoc false
  use LightningWeb, :live_view

  alias Lightning.Workflows.Workflow

  on_mount {LightningWeb.Hooks, :project_scope}

  # alias Lightning.Jobs
  # alias Lightning.Policies.{Permissions, ProjectUsers}
  # alias Lightning.Workflows
  # import LightningWeb.WorkflowLive.Components

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header socket={@socket}>
          <:title><%= @page_title %></:title>
        </LayoutComponents.header>
      </:header>
      <div class="relative h-full flex">
        <div phx-hook="WorkflowEditor" id={@project.id}>
          <!-- Before Editor component has mounted -->
          Loading...
        </div>
      </div>
    </LayoutComponents.page_content>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.project

    {:ok,
     socket
     |> assign(
       project: project,
       page_title: "Page Title",
       active_menu_item: :projects
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    job_1_id = Ecto.UUID.generate()
    job_2_id = Ecto.UUID.generate()
    trigger_1_id = Ecto.UUID.generate()

    params = %{
      "jobs" => [
        %{"id" => job_1_id, "name" => ""},
        %{"id" => job_2_id, "name" => "job-2"}
      ],
      "triggers" => [
        %{"id" => trigger_1_id, "type" => "webhook"}
      ],
      "edges" => [
        %{
          "id" => Ecto.UUID.generate(),
          "source_trigger_id" => trigger_1_id,
          "condition" => "true",
          "target_job_id" => job_1_id
        },
        %{
          "id" => Ecto.UUID.generate(),
          "source_job_id" => job_1_id,
          "condition" => ":on_success",
          "target_job_id" => job_2_id
        }
      ]
    }

    changeset = %Workflow{} |> Workflow.changeset(params)
    {:noreply, assign(socket, changeset: changeset)}
  end

  @impl true
  def handle_event("workflow-editor-mounted", _params, socket) do
    workflow_json = socket.assigns.changeset |> to_serializable()

    {:noreply, socket |> push_event("data-changed", workflow_json)}
  end

  def handle_event("update-workflow", params, socket) do
    IO.inspect(params, label: "params")
    # workflow_json = socket.assigns.changeset |> to_serializable()

    changeset = %Workflow{} |> Workflow.changeset(params)

    {:noreply,
     socket
     |> assign(changeset: changeset)
     |> push_event("data-changed", changeset |> to_serializable())}
  end

  def handle_event("add-job", params, socket) do
    IO.inspect(params, label: "params")
    # workflow_json = socket.assigns.changeset |> to_serializable()

    changeset = %Workflow{} |> Workflow.changeset(params)

    {:noreply,
     socket
     |> assign(changeset: changeset)
     |> push_event("data-changed", changeset |> to_serializable())}
  end

  # TODO: move this to a module, maybe `WorkflowJSON`?
  defp to_serializable(changeset) do
    %{
      jobs:
        changeset
        |> Ecto.Changeset.get_change(:jobs)
        |> to_serializable([:id, :name]),
      triggers:
        changeset
        |> Ecto.Changeset.get_change(:triggers)
        |> to_serializable([:id, :type]),
      edges:
        changeset
        |> Ecto.Changeset.get_change(:edges)
        |> to_serializable([
          :id,
          :source_trigger_id,
          :source_job_id,
          :condition,
          :target_job_id
        ])
    }
  end

  defp to_serializable(changesets, fields) when is_list(changesets) do
    changesets
    |> Enum.map(fn changeset ->
      changeset
      |> Ecto.Changeset.apply_changes()
      |> Map.take(fields)
      |> Map.put(
        :errors,
        Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
      )
    end)
  end
end
