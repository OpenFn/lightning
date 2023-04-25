defmodule LightningWeb.WorkflowNewLive do
  @moduledoc false
  use LightningWeb, :live_view

  alias Lightning.Workflows.Workflow
  alias LightningWeb.Components.Form

  on_mount({LightningWeb.Hooks, :project_scope})

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
          <Form.submit_button
            class=""
            phx-disable-with="Saving..."
            disabled={!@changeset.valid?}
          >
            Save
          </Form.submit_button>
        </LayoutComponents.header>
      </:header>
      <div class="relative h-full flex">
        <div phx-hook="WorkflowEditor" id={@project.id} phx-update="ignore">
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
    workflow = %Workflow{}
    job_1_id = Ecto.UUID.generate()
    job_2_id = Ecto.UUID.generate()
    trigger_1_id = Ecto.UUID.generate()

    params = %{
      "name" => "workflow-1",
      "project_id" => socket.assigns.project.id,
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

    changeset = workflow |> Workflow.changeset(params)
    workflow_params = changeset |> to_serializable()

    {:noreply,
     assign(socket,
       workflow: workflow,
       changeset: changeset,
       workflow_params: workflow_params
     )}
  end

  @impl true
  def handle_event("workflow-editor-mounted", _params, socket) do
    workflow_json = socket.assigns.changeset |> to_serializable()

    {:noreply, socket |> push_event("data-changed", workflow_json)}
  end

  def handle_event("get-initial-state", _params, socket) do
    # IO.inspect(params, label: "params")
    # workflow_json = socket.assigns.changeset |> to_serializable()

    {:reply,
     socket.assigns.workflow_params
     |> Map.put(:change_id, Ecto.UUID.generate()), socket}
  end

  # TODO: move this all into the new "Params" module
  def handle_event("push-change", %{"patches" => patches}, socket) do
    # Apply the incoming patches to the current workflow params producing a new
    # set of params.
    {:ok, params} =
      calculate_next_params(patches, socket.assigns.workflow_params)

    # Build a new changeset from the new params
    changeset = socket.assigns.workflow |> Workflow.changeset(params)

    # Prepare a new set of workflow params from the changeset
    workflow_params = changeset |> to_serializable()

    # Calculate the difference between the new params and changes introduced by
    # the changeset/validation.
    patches =
      Jsonpatch.diff(params, workflow_params)
      |> Jsonpatch.Mapper.to_map()

    {:reply, %{patches: patches},
     socket |> assign(workflow_params: workflow_params, changeset: changeset)}
  end

  defp calculate_next_params(patches, current_params) do
    Jsonpatch.apply_patch(
      patches |> Enum.map(&Jsonpatch.Mapper.from_map/1),
      current_params
    )
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
    |> Lightning.Helpers.json_safe()
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
