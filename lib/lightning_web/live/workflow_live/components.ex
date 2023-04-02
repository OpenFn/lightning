defmodule LightningWeb.WorkflowLive.Components do
  @moduledoc false
  use LightningWeb, :component

  def workflow_list(assigns) do
    ~H"""
    <div class="">
      <div class="">
        <div class="">
          <div class="py-6 md:flex md:items-center md:justify-between">
            <div class="flex-1 min-w-0">
              <h1 class="text-2xl font-bold text-gray-900 leading-7 sm:leading-9 sm:truncate">
                <%= "Project #{String.capitalize(@project.name)}" %>
              </h1>
              <dl class="flex flex-col mt-6 sm:mt-1 sm:flex-row sm:flex-wrap">
                <dd class="flex items-center text-sm font-medium text-gray-500 capitalize sm:mr-6">
                  List of workflow
                </dd>
              </dl>
            </div>
            <div class="flex mt-6 space-x-3 md:mt-0 md:ml-4">
              <LightningWeb.Components.Common.button
                phx-click="create_workflow"
                disabled={!@can_create_workflow}
              >
                Create a workflow
              </LightningWeb.Components.Common.button>
            </div>
          </div>
        </div>
      </div>
      <div class="mt-5 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
        <!--
        <.create_workflow_card can_create_workflow={@can_create_workflow} />
    -->
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
    <div class="relative px-4 pt-5 pb-12 overflow-hidden bg-white rounded-lg shadow sm:pt-6 sm:px-6">
      <dt>
        <div class="absolute p-3 bg-indigo-500 rounded-md">
          <!-- Heroicon name: outline/users -->
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="currentColor"
            class="w-6 h-6 text-white"
            viewBox="0 0 16 16"
          >
            <path d="M4.5 5a.5.5 0 1 0 0-1 .5.5 0 0 0 0 1zM3 4.5a.5.5 0 1 1-1 0 .5.5 0 0 1 1 0z" />
            <path d="M0 4a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v1a2 2 0 0 1-2 2H8.5v3a1.5 1.5 0 0 1 1.5 1.5h5.5a.5.5 0 0 1 0 1H10A1.5 1.5 0 0 1 8.5 14h-1A1.5 1.5 0 0 1 6 12.5H.5a.5.5 0 0 1 0-1H6A1.5 1.5 0 0 1 7.5 10V7H2a2 2 0 0 1-2-2V4zm1 0v1a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V4a1 1 0 0 0-1-1H2a1 1 0 0 0-1 1zm6 7.5v1a.5.5 0 0 0 .5.5h1a.5.5 0 0 0 .5-.5v-1a.5.5 0 0 0-.5-.5h-1a.5.5 0 0 0-.5.5z" />
          </svg>
        </div>
        <p class="ml-16 text-sm font-medium text-gray-500 truncate">
          <%= @workflow.name %>
        </p>
      </dt>
      <dd class="flex items-baseline pb-6 ml-16 sm:pb-7">
        <div class="flex items-baseline justify-between w-full">
          <p class="flex items-end text-2xl font-semibold text-gray-900">
            <%= Enum.count(@workflow.jobs) %> <span class="pl-2 text-sm">jobs</span>
          </p>

          <div class="flex justify-end inline-flex items-baseline px-2.5 py-0.5 rounded-full text-sm font-medium bg-green-100 text-green-800 md:mt-2 lg:mt-0">
            12%
          </div>
        </div>
        <div class="absolute inset-x-0 bottom-0 px-4 py-4 bg-gray-50 sm:px-6">
          <div class="flex justify-between text-sm">
            <.link
              navigate={
                Routes.project_workflow_path(
                  LightningWeb.Endpoint,
                  :show,
                  @project.id,
                  @workflow.id
                )
              }
              class="font-medium text-indigo-600 hover:text-indigo-500"
            >
              View
            </.link>
            <%= link(to: "#", phx_click: "delete_workflow", phx_value_id: @workflow.id, data: [ confirm: "Are you sure you'd like to delete this workflow?" ],
          class: "absolute right-2 bottom-2 p-2") do %>
              <Icon.trash class="w-6 h-6 text-red-400 hover:text-rose-700" />
            <% end %>
          </div>
        </div>
      </dd>
    </div>
    <!--
    <div class="relative">
      <.link
        class="flex items-center justify-center h-full mb-2 font-bold bg-white border shadow w-72 h-44 rounded-md hover:bg-gray-50"
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
          <Icon.trash class="w-6 h-6 text-slate-300 hover:text-rose-700" />
        <% end %>
      </.link>
    </div>
    -->
    """
  end

  def create_workflow_card(assigns) do
    ~H"""
    <div class="flex flex-col justify-between h-full p-4 bg-white border shadow w-72 h-44 rounded-md">
      <div class="mb-2 font-bold">Create a new workflow</div>
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

  attr(:socket, :map, required: true)
  attr(:project, :map, required: true)
  attr(:workflow, :map, required: true)
  attr(:disabled, :boolean, default: true)

  def create_job_panel(assigns) do
    ~H"""
    <div class="w-1/2 h-16 pt-4 mx-auto my-16 text-center">
      <div class="pb-4 text-sm font-semibold text-gray-500">
        Create your first job to get started.
      </div>
      <LightningWeb.Components.Common.button
        phx-click="create_job"
        disabled={@disabled}
      >
        <div class="h-full">
          <Heroicons.plus class="inline-block w-4 h-4" />
          <span class="inline-block align-middle">
            Create job
          </span>
        </div>
      </LightningWeb.Components.Common.button>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:encoded_project_space, :string, required: true)
  attr(:selected_node, :string, default: nil)
  attr(:base_path, :string, required: true)

  def workflow_diagram(assigns) do
    ~H"""
    <div
      phx-hook="WorkflowDiagram"
      class="w-full h-full"
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
