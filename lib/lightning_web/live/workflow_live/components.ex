defmodule LightningWeb.WorkflowLive.Components do
  @moduledoc false
  use LightningWeb, :component

  def workflow_list(assigns) do
    ~H"""
    <div class="w-full">
      <div class="w-full flex flex-wrap gap-4">
        <.create_workflow_card can_create_workflow={@can_create_workflow} />
        <%= for workflow <- @workflows do %>
          <.workflow_card
            workflow={%{workflow | name: workflow.name || "Untitled"}}
            project={@project}
          />
        <% end %>
      </div>
    </div>
    """
  end

  def workflow_card(assigns) do
    ~H"""
    <div class="relative">
      <.link
        class="w-72 h-44 bg-white rounded-md border shadow flex h-full justify-center items-center font-bold mb-2 hover:bg-gray-50"
        navigate={
          Routes.project_workflow_path(
            LightningWeb.Endpoint,
            :show,
            @project.id,
            @workflow.id
          )
        }
      >
        <%= @workflow.name %>

        <%= link(
          to: "#",
          phx_click: "delete_workflow",
          phx_value_id: @workflow.id,
          data: [ confirm: "Are you sure you'd like to delete this workflow?" ],
          class: "absolute right-2 bottom-2 p-2") do %>
          <Icon.trash class="h-6 w-6 text-slate-300 hover:text-rose-700" />
        <% end %>
      </.link>
    </div>
    """
  end

  def create_workflow_card(assigns) do
    ~H"""
    <div class="w-72 h-44 bg-white rounded-md border shadow p-4 flex flex-col h-full justify-between">
      <div class="font-bold mb-2">Create a new workflow</div>
      <div class="">Create a new workflow for your organisation</div>
      <div>
        <LightningWeb.Components.Common.button
          phx-click="create_workflow"
          disabled={!@can_create_workflow}
        >
          Create a workflow
        </LightningWeb.Components.Common.button>
      </div>
    </div>
    """
  end

  attr :socket, :map, required: true
  attr :project, :map, required: true
  attr :workflow, :map, required: true
  attr :disabled, :boolean, default: true

  def create_job_panel(assigns) do
    ~H"""
    <div class="w-1/2 h-16 text-center my-16 mx-auto pt-4">
      <div class="text-sm font-semibold text-gray-500 pb-4">
        Create your first job to get started.
      </div>
      <LightningWeb.Components.Common.button
        phx-click="create_job"
        disabled={@disabled}
      >
        <div class="h-full">
          <Heroicons.plus class="h-4 w-4 inline-block" />
          <span class="inline-block align-middle">
            Create job
          </span>
        </div>
      </LightningWeb.Components.Common.button>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :encoded_project_space, :string, required: true
  attr :selected_node, :string, default: nil
  attr :base_path, :string, required: true

  def workflow_diagram(assigns) do
    ~H"""
    <div
      phx-hook="WorkflowDiagram"
      class="h-full w-full"
      id={"hook-#{@id}"}
      phx-update="ignore"
      base-path={@base_path}
      data-selected-node={@selected_node}
      data-project-space={@encoded_project_space}
    >
    </div>
    """
  end
end
