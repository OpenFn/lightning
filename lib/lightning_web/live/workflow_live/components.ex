defmodule LightningWeb.WorkflowLive.Components do
  @moduledoc false
  use LightningWeb, :component
  alias Phoenix.LiveView.JS

  attr :active, :boolean, default: true
  attr :toggle_content, :boolean, required: true
  attr :project, :map, required: true
  attr :workflows, :map, required: true
  attr :name, :string, default: ""
  attr :search, :boolean
  attr :can_create_workflow, :boolean

  def workflow_list(assigns) do
    ~H"""
    <div class="py-6">
      <.workflow_header
        project={@project}
        toggle_content={@toggle_content}
        can_create_workflow={@can_create_workflow}
        name={@name}
      />
      <div class="mt-5 grid grid-cols-1 gap-5 lg:grid-cols-3">
        <%= for workflow <- @workflows do %>
          <.workflow_card
            workflow={%{workflow | name: workflow.name || "Untitled"}}
            project={@project}
            workflows={@workflows}
          />
        <% end %>
      </div>
      <%= if length(@workflows) == 0 do %>
        <.empty_state
          can_create_workflow={@can_create_workflow}
          search={@search}
          project={@project}
        />
      <% end %>
    </div>
    """
  end

  def workflow_card(assigns) do
    ~H"""
    <.confirm_modal id={@workflow.id} />
    <div
      class="relative px-4 pt-5 pb-12 overflow-hidden bg-white rounded-lg shadow sm:pt-6 sm:px-6"
      id={@workflow.id}
    >
      <dt class="" id="data-list">
        <div class="absolute p-3 bg-indigo-500 rounded-md">
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
        <p class="ml-16 text-sm font-medium text-gray-500 truncate" id="title-header">
          <%= @workflow.name %>
        </p>
      </dt>
      <dd class="flex items-baseline pb-6 ml-16 sm:pb-7">
        <div class="flex items-baseline justify-between w-full" id="content">
          <p class="flex items-end text-2xl font-semibold text-gray-900">
            <%= Enum.count(@workflow.jobs) %>
            <span class="pl-2 text-sm">jobs</span>
          </p>

          <.link navigate={~p"/projects/#{@project.id}/runs"} class="flex justify-end inline-flex items-baseline px-2.5 py-0.5 rounded-full text-sm font-medium bg-green-100 text-green-800 md:mt-2 lg:mt-0">
            <%= "#{success_metric(@workflow)}" %>
          </.link>
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
            <a
              href="#"
              phx-click={show_modal("#confirm-modal-#{@workflow.id}", @workflow.id)}
            >
              <Icon.trash class="w-6 h-6 text-red-400 hover:text-rose-700" />
            </a>
          </div>
        </div>
      </dd>
    </div>
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

  attr :socket, :map, required: true
  attr :project, :map, required: true
  attr :workflow, :map, required: true
  attr :disabled, :boolean, default: true

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

  attr :id, :string, required: true
  attr :encoded_project_space, :string, required: true
  attr :selected_node, :string, default: nil
  attr :base_path, :string, required: true

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

  def workflow_header(assigns) do
    ~H"""
    <h1 class="text-2xl font-bold text-gray-900 leading-7 sm:leading-9 sm:truncate">
      <%= "Project #{String.capitalize(@project.name)}" %>
    </h1>
    <div class="flex mt-4 md:items-end md:justify-between">
      <div class="justify-start flex-1 hidden lg:flex">
        <div class="w-1/2">
          <div class="relative text-indigo-400 focus-within:text-gray-400">
            <div class="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none">
              <Heroicons.magnifying_glass class="w-5 h-5" />
            </div>
            <form phx-change="search_workflow">
              <input
                id="search"
                name="name"
                value={@name}
                phx-debounce="500"
                class="block w-full py-2 pl-10 pr-3 text-indigo-800 placeholder-gray-500 border border-transparent rounded-md leading-5 bg-opacity-25 focus:outline-none focus:bg-white focus:ring-0 focus:placeholder-gray-400 focus:text-gray-900 sm:text-sm"
                placeholder="Search workflows..."
                type="search"
              />
            </form>
          </div>
        </div>
      </div>
      <div class="flex mt-0 mt-6 lg:space-x-3 lg:ml-4">
        <div class="hidden mr-8 md:flex items-center space-x-1.5">
          <button
            phx-click={hide_content("#content", @toggle_content)}
            class={"inline-flex items-center justify-center px-3 py-2 text-sm font-semibold text-gray-900 rounded-lg dark:text-gray-400 #{toggle_class(!@toggle_content)}"}
          >
            <Heroicons.bars_2
              solid
              stroke-width="2"
              class="w-5 h-5 text-gray-800 dark:text-gray-400"
            />
          </button>
          <button
            phx-click={show_content("#content", @toggle_content)}
            class={"inline-flex items-center justify-center px-3 py-2 text-sm font-semibold text-gray-900 rounded-lg dark:text-gray-400 #{toggle_class(@toggle_content)}"}
          >
            <Heroicons.bars_3_bottom_left
              outline
              stroke-width="2"
              class="w-5 h-5 text-gray-800 dark:text-gray-400"
            />
          </button>
        </div>

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

  def empty_state(assigns) do
    ~H"""
    <div class="w-full px-4 mx-auto mt-4 bg-white rounded-lg shadow-lg sm:px-6 lg:px-8">
      <div class="text-center py-14">
        <Heroicons.folder_plus outline class="w-12 h-12 mx-auto text-gray-400" />
        <%= if @search == false do %>
          <h3 class="mt-6 text-base font-medium text-gray-900">
            There are no worflows for this Project.
          </h3>
          <div class="mt-4 text-sm text-gray-500">
            <button
              class="font-medium text-blue-600 hover:cursor-pointer"
              phx-click="create_workflow"
              type="button"
              id="create_workflow"
            >
              Create a new workflow
            </button>
            now to get started. These worflows will be associated with this project.
          </div>
        <% else %>
          <h3 class="mt-6 text-base font-medium text-gray-900">
            We could't find any workflow that matches your search.
          </h3>
          <div class="mt-4 text-sm text-gray-500">
            <.link
              navigate={~p"/projects/#{@project.id}/w"}
              class="font-medium text-blue-600 hover:cursor-pointer"
              phx-click="create_workflow"
              type="button"
            >
              Clear Search
            </.link>
          </div>
        <% end %>
        <div class="mt-6"></div>
      </div>
    </div>
    """
  end

  def confirm_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-20 hidden overflow-y-auto"
      aria-labelledby="modal-title"
      role="dialog"
      aria-modal="true"
      id={"confirm-modal-#{@id}"}
      phx-click={cancel_modal("#confirm-modal-#{@id}")}
      phx-window-keydown={cancel_modal("#confirm-modal-#{@id}")}
      phx-key="escape"
    >
      <div class="flex items-end justify-center min-h-screen px-4 pt-4 pb-20 text-center sm:block sm:p-0">
        <div
          class="fixed inset-0 bg-gray-500 bg-opacity-50 transition-opacity"
          aria-hidden="true"
        >
        </div>
        <span
          class="hidden sm:inline-block sm:align-middle sm:h-screen"
          aria-hidden="true"
        >
          &#8203;
        </span>
        <div class="relative inline-block overflow-hidden text-left align-bottom bg-white rounded-lg shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full">
          <div class="px-4 pt-5 pb-4 bg-white sm:p-6 sm:pb-4">
            <div class="sm:flex sm:items-start">
              <div class="flex items-center justify-center flex-shrink-0 w-12 h-12 mx-auto bg-red-100 rounded-full sm:mx-0 sm:h-10 sm:w-10">
                <Heroicons.exclamation_triangle class="w-6 text-red-600" />
              </div>
              <div class="mt-3 text-center sm:mt-0 sm:ml-4 sm:text-left">
                <h3
                  class="text-lg font-medium text-gray-900 leading-6"
                  id="modal-title"
                >
                  Delete workflow
                </h3>
                <div class="mt-2">
                  <p class="text-sm text-gray-500">
                    Are you sure you want to delete the workflow? All of your data will be permanently removed. This action cannot be undone.
                  </p>
                </div>
              </div>
            </div>
          </div>
          <div class="px-4 py-3 bg-gray-50 sm:px-6 sm:flex sm:flex-row-reverse">
            <button
              type="button"
              phx-click={delete_modal("#confirm-modal-#{@id}", @id)}
              class="inline-flex justify-center w-full px-4 py-2 text-base font-medium text-white bg-red-600 border border-transparent rounded-md shadow-sm hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500 sm:ml-3 sm:w-auto sm:text-sm"
            >
              Delete
            </button>
            <button
              type="button"
              phx-click={cancel_modal("#confirm-modal-#{@id}")}
              class="inline-flex justify-center w-full px-4 py-2 mt-3 text-base font-medium text-gray-700 bg-white border border-gray-300 rounded-md shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:mt-0 sm:ml-3 sm:w-auto sm:text-sm"
            >
              Cancel
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end


  def success_metric(workflow) do
    work_orders = Enum.count(workflow.work_orders)

    success = Enum.count(List.first(workflow.jobs).runs, &(&1.exit_code == 0))

    if success > 0 do
     metric = (success / work_orders) * 100
     "#{round(metric)} %"
    else
      "running..."
    end

  end

  def show_modal(id, _workflow, js \\ %JS{}) do
    js
    |> JS.remove_class("hidden", to: id)
  end

  def delete_modal(id, workflow, js \\ %JS{}) do
    js
    |> JS.push("delete_workflow", value: %{id: workflow})
    |> JS.add_class("hidden", to: id)
  end

  def cancel_modal(id, js \\ %JS{}) do
    js
    |> JS.add_class("hidden", to: id)
  end

  def hide_content(id, _active, js \\ %JS{}) do
    js
    |> JS.push("hide-body")
    |> JS.add_class("hidden", to: id)
    |> JS.remove_class("text-sm", to: "#title-header")
    |> JS.add_class("text-lg", to: "#title-header")
    |> JS.add_class("flex items-center", to: "#data-list")
  end

  def show_content(id, _active, js \\ %JS{}) do
    js
    |> JS.push("show-body")
    |> JS.remove_class("hidden", to: id)
    |> JS.add_class("text-sm", to: "#title-header")
    |> JS.remove_class("text-lg", to: "#title-header")
    |> JS.remove_class("flex items-center", to: "#data-list")
  end

  def toggle_class(active) do
    case active do
      true -> "bg-gray-200"
      false -> ""
    end
  end

  attr(:id, :string, required: true)

  def resize_component(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="JobEditorResizer"
      phx-update="ignore"
      class="w-2 h-full resize-x bg-slate-200 cursor-col-resize z-11"
    >
    </div>
    """
  end
end
