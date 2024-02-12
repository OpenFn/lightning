defmodule LightningWeb.RunLive.RunViewerLive do
  use LightningWeb, {:live_view, container: {:div, []}}
  use LightningWeb.RunLive.Streaming, chunk_size: 100

  import LightningWeb.RunLive.Components

  alias Lightning.Accounts.User
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias LightningWeb.Components.Viewers
  alias Phoenix.LiveView.AsyncResult

  require Lightning.Run

  @impl true
  def render(assigns) do
    ~H"""
    <div class="@container/viewer h-full">
      <.async_result :let={run} assign={@run}>
        <:loading>
          <.loading_filler />
        </:loading>
        <:failed :let={_reason}>
          There was an error loading the Run.
        </:failed>

        <div class="flex @5xl/viewer:gap-6 h-full @5xl/viewer:flex-row flex-col">
          <div class="flex-none flex gap-6 @5xl/viewer:flex-col flex-row">
            <.detail_list id={"run-detail-#{run.id}"}>
              <.list_item>
                <:label class="whitespace-nowrap">Work Order</:label>
                <:value>
                  <.link
                    navigate={
                      ~p"/projects/#{@project}/history?#{%{filters: %{workorder_id: run.work_order_id}}}"
                    }
                    class="hover:underline hover:text-primary-900"
                  >
                    <span class="whitespace-nowrap text-ellipsis">
                      <%= display_short_uuid(run.work_order_id) %>
                    </span>
                    <.icon name="hero-arrow-up-right" class="h-2 w-2 float-right" />
                  </.link>
                </:value>
              </.list_item>
              <.list_item>
                <:label>Run</:label>
                <:value>
                  <.link
                    navigate={
                      ~p"/projects/#{@project}/runs/#{run}?step=#{@selected_step_id || ""}"
                    }
                    class="hover:underline hover:text-primary-900 whitespace-nowrap text-ellipsis"
                  >
                    <span class="whitespace-nowrap text-ellipsis">
                      <%= display_short_uuid(run.id) %>
                    </span>
                    <.icon name="hero-arrow-up-right" class="h-2 w-2 float-right" />
                  </.link>
                </:value>
              </.list_item>
              <.list_item>
                <:label>Started</:label>
                <:value>
                  <%= if run.started_at,
                    do:
                      Timex.Format.DateTime.Formatters.Relative.format!(
                        run.started_at,
                        "{relative}"
                      ) %>
                </:value>
              </.list_item>
              <.list_item>
                <:label>Duration</:label>
                <:value>
                  <.elapsed_indicator run={run} />
                </:value>
              </.list_item>
              <.list_item>
                <:label>Status</:label>
                <:value><.state_pill state={run.state} /></:value>
              </.list_item>
            </.detail_list>

            <.step_list
              :let={step}
              id={"step-list-#{run.id}"}
              steps={@steps}
              class="flex-1"
            >
              <.step_item
                step={step}
                is_clone={DateTime.compare(step.inserted_at, run.inserted_at) == :lt}
                phx-click="select_step"
                phx-value-id={step.id}
                selected={step.id == @selected_step_id}
                class="cursor-pointer"
              />
            </.step_list>
          </div>
          <div class="grow flex flex-col gap-4 min-h-0">
            <Common.tab_bar orientation="horizontal" id="1" default_hash="log">
              <Common.tab_item orientation="horizontal" hash="log">
                <.icon
                  name="hero-command-line"
                  class="h-5 w-5 inline-block mr-1 align-middle"
                />
                <span class="inline-block align-middle">Log</span>
              </Common.tab_item>
              <Common.tab_item orientation="horizontal" hash="input">
                <.icon
                  name="hero-arrow-down-on-square"
                  class="h-5 w-5 inline-block mr-1 align-middle"
                />
                <span class="inline-block align-middle">Input</span>
              </Common.tab_item>
              <Common.tab_item orientation="horizontal" hash="output">
                <.icon
                  name="hero-arrow-up-on-square"
                  class="h-5 w-5 inline-block mr-1 align-middle"
                />
                <span class="inline-block align-middle">
                  Output
                </span>
              </Common.tab_item>
            </Common.tab_bar>

            <div class="min-h-0 grow flex overflow-auto">
              <Common.panel_content
                for_hash="log"
                class="grow overflow-auto rounded-md shadow-sm bg-slate-700 border-slate-300"
              >
                <Viewers.log_viewer
                  id={"run-log-#{run.id}"}
                  highlight_id={@selected_step_id}
                  stream={@streams.log_lines}
                  stream_empty?={@log_lines_stream_empty?}
                />
              </Common.panel_content>
              <Common.panel_content for_hash="input" class="grow overflow-auto">
                <%= if @run.ok? && @run.result.state in Lightning.Run.final_states() && is_nil(@selected_step_id) do %>
                  <div class="border-2 border-gray-200 border-dashed rounded-lg px-8 pt-6 pb-8 mb-4 flex flex-col">
                    <p class="text-sm text-center">
                      No input/output available. This step was never started.
                    </p>
                  </div>
                <% else %>
                  <Viewers.step_dataclip_viewer
                    id={"step-input-#{@selected_step_id}"}
                    class="overflow-auto h-full"
                    stream={@streams.input_dataclip}
                    stream_empty?={@input_dataclip_stream_empty?}
                    step={@selected_step}
                    dataclip={@input_dataclip}
                    input_or_output={:input}
                    project_id={@project.id}
                    admin_contacts={@admin_contacts}
                    can_edit_data_retention={@can_edit_data_retention}
                  />
                <% end %>
              </Common.panel_content>
              <Common.panel_content for_hash="output" class="grow overflow-auto">
                <%= if @run.ok? && @run.result.state in Lightning.Run.final_states() && is_nil(@selected_step_id) do %>
                  <div class="border-2 border-gray-200 border-dashed rounded-lg px-8 pt-6 pb-8 mb-4 flex flex-col">
                    <p class="text-sm text-center">
                      No input/output available. This step was never started.
                    </p>
                  </div>
                <% else %>
                  <Viewers.step_dataclip_viewer
                    id={"step-output-#{@selected_step_id}"}
                    class="overflow-auto h-full"
                    stream={@streams.output_dataclip}
                    stream_empty?={@output_dataclip_stream_empty?}
                    step={@selected_step}
                    dataclip={@output_dataclip}
                    input_or_output={:output}
                    project_id={@project.id}
                    admin_contacts={@admin_contacts}
                    can_edit_data_retention={@can_edit_data_retention}
                  />
                <% end %>
              </Common.panel_content>
            </div>
          </div>
        </div>
      </.async_result>
    </div>
    """
  end

  @impl true
  def mount(
        _params,
        %{
          "run_id" => run_id,
          "project_id" => project_id,
          "user_id" => user_id
        } = session,
        socket
      ) do
    project_user =
      Projects.get_project_user(%Project{id: project_id}, %User{id: user_id})

    {:ok,
     socket
     |> assign(
       selected_step_id: nil,
       job_id: Map.get(session, "job_id"),
       steps: []
     )
     |> stream(:log_lines, [])
     |> assign(:log_lines_stream_empty?, true)
     |> stream(:input_dataclip, [])
     |> assign(:input_dataclip_stream_empty?, true)
     |> assign(:input_dataclip, false)
     |> stream(:output_dataclip, [])
     |> assign(:output_dataclip_stream_empty?, true)
     |> assign(:output_dataclip, false)
     |> assign(:run, AsyncResult.loading())
     |> assign(:log_lines, AsyncResult.loading())
     |> assign(
       can_edit_data_retention:
         Permissions.can?(
           ProjectUsers,
           :edit_data_retention,
           %User{id: user_id},
           project_user
         )
     )
     |> assign(admin_contacts: Projects.list_project_admin_emails(project_id))
     |> get_run_async(run_id), layout: false}
  end

  @impl true
  def handle_event("select_step", %{"id" => id}, socket) do
    {:noreply, socket |> apply_selected_step_id(id)}
  end

  @impl true
  def handle_info(%Lightning.Runs.Events.DataclipUpdated{}, socket) do
    {:noreply, socket}
  end

  def handle_steps_change(socket) do
    # either a job_id or a step_id is passed in
    # if a step_id is passed in, we can highlight the log lines immediately
    # if a job_id is passed in, we need to wait for the step to start
    # if neither is passed in, we can't highlight anything

    %{job_id: job_id, steps: steps} = socket.assigns

    selected_step_id =
      socket.assigns.selected_step_id || get_step_id_for_job_id(job_id, steps)

    selected_step = steps |> Enum.find(&(&1.id == selected_step_id))

    socket
    |> assign(selected_step_id: selected_step_id, selected_step: selected_step)
    |> maybe_load_input_dataclip()
    |> maybe_load_output_dataclip()
  end

  defp get_step_id_for_job_id(job_id, steps) do
    steps
    |> Enum.find(%{}, &(&1.job_id == job_id))
    |> Map.get(:id)
  end
end
