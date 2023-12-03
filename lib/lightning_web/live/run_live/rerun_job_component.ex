defmodule LightningWeb.RunLive.RerunJobComponent do
  @moduledoc """
  Rerun job component
  """

  use LightningWeb, :live_component
  alias Lightning.Jobs
  alias Lightning.Workflows

  @impl true
  def update(
        %{
          total_entries: _count,
          selected_count: _selected_count,
          workflow_id: workflow_id
        } = assigns,
        socket
      ) do
    workflow = Workflows.get_workflow!(workflow_id)
    jobs = Jobs.list_jobs_for_workflow(workflow)

    {:ok,
     socket
     |> assign(
       show: false,
       workflow: workflow,
       workflow_jobs: jobs,
       selected_job: hd(jobs)
     )
     |> assign(assigns)}
  end

  @impl true
  def handle_event(
        "select_job",
        %{"job" => job_id},
        %{assigns: assigns} = socket
      ) do
    selected_job =
      Enum.find(assigns.workflow_jobs, fn job -> job.id == job_id end)

    {:noreply, assign(socket, selected_job: selected_job)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="relative z-10 hidden"
      aria-labelledby={"#{@id}-title"}
      id={@id}
      role="dialog"
      aria-modal="true"
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
    >
      <div
        id={"#{@id}-bg"}
        class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"
      >
      </div>

      <div
        aria-labelledby={"#{@id}-title"}
        class="fixed inset-0 z-10 overflow-y-auto"
      >
        <div class="flex min-h-full items-end justify-center p-4 text-center sm:items-center sm:p-0">
          <.focus_wrap
            id={"#{@id}-container"}
            phx-mounted={@show && show_modal(@id)}
            phx-window-keydown={hide_modal(@id)}
            phx-key="escape"
            phx-click-away={hide_modal(@id)}
            class="hidden relative transform overflow-hidden rounded-lg bg-white px-4 pb-4 pt-5 text-left shadow-xl transition-all sm:my-8 sm:w-full sm:max-w-lg sm:p-6"
          >
            <div id={"#{@id}-content"} class="mt-3 text-center sm:mt-5">
              <h3
                class="text-base font-semibold leading-6 text-gray-900"
                id={"#{@id}-title"}
              >
                Run from a specific step
              </h3>
              <div class="mt-2">
                <p class="text-sm text-gray-500">
                  Find all runs that include this step and rerun from there. (Note that if you'd like to reprocess all of the selected workorders from the start, use the "Rerun" button, not this "Rerun from" button.)
                </p>
                <form
                  id="select-job-for-rerun-form"
                  phx-change="select_job"
                  phx-target={@myself}
                >
                  <fieldset class="mt-4">
                    <legend class="sr-only">Workflow Job</legend>
                    <div class="space-y-4">
                      <%= for job <- @workflow_jobs do %>
                        <div class="flex items-center">
                          <input
                            id={"job_#{job.id}"}
                            name="job"
                            type="radio"
                            class="h-4 w-4 border-gray-300 text-indigo-600 focus:ring-indigo-600"
                            value={job.id}
                            checked={
                              if job.id == @selected_job.id,
                                do: "checked",
                                else: false
                            }
                          />
                          <label
                            for={"job_#{job.id}"}
                            class="ml-3 block text-sm font-medium leading-6 text-gray-900"
                          >
                            <%= job.name %>
                          </label>
                        </div>
                      <% end %>
                    </div>
                  </fieldset>
                </form>
              </div>
            </div>
            <div
              :if={@all_selected? and @total_entries > 1 and @pages > 1}
              class="mt-5 sm:mt-6 sm:grid sm:grid-flow-row-dense sm:grid-cols-2 sm:gap-3"
            >
              <button
                id="rerun-selected-from-job-trigger"
                type="button"
                phx-click="bulk-rerun"
                phx-value-type="selected"
                phx-value-job={@selected_job.id}
                phx-disable-with="Running..."
                class="inline-flex w-full justify-center rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600 sm:col-start-1"
              >
                Rerun <%= @selected_count %> selected workorder<%= if @selected_count >
                                                                        1,
                                                                      do: "s",
                                                                      else: "" %> from selected job
              </button>
              <button
                id="rerun-all-from-job-trigger"
                type="button"
                phx-click="bulk-rerun"
                phx-value-type="all"
                phx-value-job={@selected_job.id}
                phx-disable-with="Running..."
                class="inline-flex w-full justify-center rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600 sm:col-start-2"
              >
                Rerun all <%= @total_entries %> matching workorders from selected job
              </button>
              <div class="relative col-start-1 col-end-3">
                <div class="absolute inset-0 flex items-center" aria-hidden="true">
                  <div class="w-full border-t border-gray-300"></div>
                </div>
                <div class="relative flex justify-center">
                  <span class="bg-white px-2 text-sm text-gray-500">
                    OR
                  </span>
                </div>
              </div>
              <button
                type="button"
                class="mt-3 inline-flex w-full justify-center items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:col-start-1 sm:col-end-3 sm:mt-0"
                phx-click={hide_modal(@id)}
              >
                Cancel
              </button>
            </div>
            <div
              :if={!@all_selected? or @total_entries == 1 or @pages == 1}
              class="mt-5 sm:mt-6 sm:grid sm:grid-flow-row-dense sm:grid-cols-2 sm:gap-3"
            >
              <button
                id="rerun-selected-from-job-trigger"
                type="button"
                phx-click="bulk-rerun"
                phx-value-type="selected"
                phx-value-job={@selected_job.id}
                phx-disable-with="Running..."
                class="inline-flex w-full justify-center rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600 sm:col-start-2"
              >
                Rerun <%= @selected_count %> selected workorder<%= if @selected_count >
                                                                        1,
                                                                      do: "s",
                                                                      else: "" %> from selected job
              </button>
              <button
                type="button"
                class="mt-3 inline-flex w-full justify-center items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:col-start-1 sm:mt-0"
                phx-click={hide_modal(@id)}
              >
                Cancel
              </button>
            </div>
          </.focus_wrap>
        </div>
      </div>
    </div>
    """
  end
end
