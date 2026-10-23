defmodule LightningWeb.WorkflowLive.Health do
  @moduledoc """
  Workflow health page: a summary of a single workflow's work orders over the
  window the reader picks. The design system's page draws it; the page asks
  the health endpoints for its numbers itself.
  """
  use LightningWeb, :live_view

  alias Lightning.Workflows

  on_mount {LightningWeb.Hooks, :project_scope}
  on_mount {LightningWeb.Hooks, :ensure_workflow_belongs_to_project}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    workflow = Workflows.get_workflow!(id)

    {:ok,
     assign(socket,
       active_menu_item: :overview,
       workflow: workflow,
       page_title: "Health Stats for #{workflow.name}"
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.design_system_page
      name="WorkflowHealthPage"
      props={page_props(assigns)}
      banner={assigns[:banner]}
      current_user={@current_user}
    />
    """
  end

  # The shape the design system's WorkflowHealthPageProps expect, minus the
  # range and the endpoint replies, which the page keeps itself.
  defp page_props(%{project: project, workflow: workflow} = assigns) do
    %{
      project: %{
        id: project.id,
        parentId: project.parent_id,
        color: project.color,
        historyRetentionPeriod: project.history_retention_period
      },
      projectLabel: assigns.project_label,
      workflow: %{id: workflow.id, name: workflow.name}
    }
  end
end
