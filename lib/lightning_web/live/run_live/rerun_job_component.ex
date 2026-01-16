defmodule LightningWeb.RunLive.RerunJobComponent do
  @moduledoc """
  Rerun job component
  """
  use LightningWeb, :live_component

  import LightningWeb.Utils, only: [pluralize_with_s: 2]

  alias Lightning.Jobs
  alias Lightning.Workflows
  alias Lightning.WorkOrders

  @impl true
  def update(
        %{
          total_entries: _count,
          selected_workorders:
            [%{workflow_id: workflow_id} | _] = selected_workorders
        } = assigns,
        socket
      ) do
    workflow = Workflows.get_workflow!(workflow_id)
    workflow_jobs = Jobs.list_jobs_for_workflow(workflow)

    {retriable_jobs_ids, retriable_count_per_job} =
      selected_workorders
      |> WorkOrders.get_last_runs_steps_with_dataclips(workflow_jobs)
      |> then(fn run_steps ->
        retriable_jobs_ids = MapSet.new(run_steps, & &1.step.job_id)

        retriable_count_per_job =
          run_steps
          |> Enum.group_by(& &1.step.job_id, & &1.run.work_order_id)
          |> Map.new(fn {job_id, workorder_ids} ->
            {job_id, Enum.count(workorder_ids)}
          end)

        {retriable_jobs_ids, retriable_count_per_job}
      end)

    disabled_jobs_ids =
      MapSet.difference(MapSet.new(workflow_jobs, & &1.id), retriable_jobs_ids)

    {:ok,
     socket
     |> assign(
       show: false,
       workflow: workflow,
       workflow_jobs: workflow_jobs,
       disabled_jobs_ids: disabled_jobs_ids,
       retriable_count_per_job: retriable_count_per_job
     )
     |> update_selected_job(hd(workflow_jobs).id)
     |> assign(assigns)}
  end

  @impl true
  def handle_event(
        "select_job",
        %{"job" => job_id},
        socket
      ) do
    {:noreply, update_selected_job(socket, job_id)}
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
      <div id={"#{@id}-bg"} class="modal-backdrop" />

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
                  Find all runs that include this step and rerun from there. (Note that if you'd like to reprocess all of the selected work orders from the start, use the "Rerun" button, not this "Rerun from" button.)
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
                            disabled={MapSet.member?(@disabled_jobs_ids, job.id)}
                          />
                          <label
                            id={"jobl_#{job.id}"}
                            for={"job_#{job.id}"}
                            class={[
                              "ml-3 block text-sm leading-6 font-medium",
                              "#{if MapSet.member?(@disabled_jobs_ids, job.id), do: "text-slate-500", else: "text-gray-900"}"
                            ]}
                          >
                            {job.name}
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
              <.button
                id="rerun-selected-from-job-trigger"
                type="button"
                theme="primary"
                phx-click="bulk-rerun"
                phx-value-type="selected"
                phx-value-job={@selected_job.id}
                phx-disable-with="Running..."
                class="w-full sm:col-start-1"
              >
                Rerun {@retriable_count} selected work {pluralize_with_s(
                  @retriable_count,
                  "order"
                )} from selected job
              </.button>
              <.button
                id="rerun-all-from-job-trigger"
                type="button"
                theme="primary"
                phx-click="bulk-rerun"
                phx-value-type="all"
                phx-value-job={@selected_job.id}
                phx-disable-with="Running..."
                class="w-full sm:col-start-2"
              >
                Rerun all {@total_entries} matching work orders from selected job
              </.button>
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
              <.button
                type="button"
                theme="secondary"
                class="w-full sm:col-start-1 sm:col-end-3"
                phx-click={hide_modal(@id)}
              >
                Cancel
              </.button>
            </div>
            <div
              :if={!@all_selected? or @total_entries == 1 or @pages == 1}
              class="mt-5 sm:mt-6 sm:grid sm:grid-flow-row-dense sm:grid-cols-2 sm:gap-3"
            >
              <.button
                id="rerun-selected-from-job-trigger"
                type="button"
                theme="primary"
                phx-click="bulk-rerun"
                phx-value-type="selected"
                phx-value-job={@selected_job.id}
                phx-disable-with="Running..."
                class="w-full sm:col-start-2"
              >
                Rerun {@retriable_count} selected work {pluralize_with_s(
                  @retriable_count,
                  "order"
                )} from selected job
              </.button>
              <.button
                type="button"
                theme="secondary"
                class="w-full sm:col-start-1"
                phx-click={hide_modal(@id)}
              >
                Cancel
              </.button>
            </div>
          </.focus_wrap>
        </div>
      </div>
    </div>
    """
  end

  defp update_selected_job(socket, job_id) do
    %{
      retriable_count_per_job: retriable_count_per_job,
      workflow_jobs: workflow_jobs
    } = socket.assigns

    selected_job =
      Enum.find(workflow_jobs, fn job -> job.id == job_id end)

    assign(socket,
      selected_job: selected_job,
      retriable_count: Map.get(retriable_count_per_job, selected_job.id)
    )
  end
end
