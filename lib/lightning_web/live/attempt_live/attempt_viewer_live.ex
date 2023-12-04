defmodule LightningWeb.AttemptLive.AttemptViewerLive do
  use LightningWeb, {:live_view, container: {:div, []}}

  import LightningWeb.AttemptLive.Components
  alias LightningWeb.Components.Viewers
  alias Lightning.Attempts

  alias Phoenix.LiveView.AsyncResult
  alias LightningWeb.AttemptLive.Streaming

  @impl true
  def render(assigns) do
    ~H"""
    <div class="@container/viewer h-full">
      <.async_result :let={attempt} assign={@attempt}>
        <:loading>
          <.loading_filler />
        </:loading>
        <:failed :let={_reason}>
          There was an error loading the Attempt.
        </:failed>

        <div class="flex @5xl/viewer:gap-6 h-full @5xl/viewer:flex-row flex-col">
          <div class="flex-none flex gap-6 @5xl/viewer:flex-col flex-row">
            <.attempt_detail
              show_url={
                ~p"/projects/#{attempt.work_order.workflow.project}/attempts/#{attempt}/"
              }
              attempt={attempt}
              class="flex-1 @5xl/viewer:flex-none"
            />

            <.step_list
              :let={run}
              id={"step-list-#{attempt.id}"}
              runs={@runs}
              class="flex-1"
            >
              <.step_item
                run={run}
                selected={run.id == @selected_run_id}
                class="cursor-default"
              />
            </.step_list>
          </div>
          <div class="grow-0 flex flex-col gap-4 min-h-0">
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
              <Common.panel_content for_hash="log" class="grow overflow-auto">
                <Viewers.log_viewer
                  id={"attempt-log-#{attempt.id}"}
                  class="overflow-auto h-full"
                  highlight_id={@selected_run_id}
                  stream={@streams.log_lines}
                />
              </Common.panel_content>
              <Common.panel_content for_hash="input" class="grow overflow-auto">
                <Viewers.dataclip_viewer
                  id={"run-input-#{@selected_run_id}"}
                  class="overflow-auto h-full flex"
                  stream={@streams.input_dataclip}
                />
              </Common.panel_content>
              <Common.panel_content for_hash="output" class="grow overflow-auto">
                <Viewers.dataclip_viewer
                  id={"run-output-#{@selected_run_id}"}
                  class="overflow-auto h-full"
                  stream={@streams.output_dataclip}
                />
              </Common.panel_content>
            </div>
          </div>
        </div>
      </.async_result>
    </div>
    """
  end

  @impl true
  def mount(_params, %{"attempt_id" => attempt_id} = session, socket) do
    {:ok,
     socket
     |> assign(
       selected_run_id: nil,
       job_id: Map.get(session, "job_id"),
       runs: []
     )
     |> stream(:log_lines, [])
     |> stream(:input_dataclip, [])
     |> assign(:input_dataclip, false)
     |> stream(:output_dataclip, [])
     |> assign(:output_dataclip, false)
     |> assign(:attempt, AsyncResult.loading())
     |> assign(:log_lines, AsyncResult.loading())
     |> start_async(:attempt, fn ->
       Attempts.get(attempt_id, include: [runs: :job, workflow: :project])
     end), layout: false}
  end

  use Streaming, chunk_size: 100

  def handle_runs_change(socket) do
    # either a job_id or a run_id is passed in
    # if a run_id is passed in, we can hightlight the log lines immediately
    # if a job_id is passed in, we need to wait for the run to start
    # if neither is passed in, we can't highlight anything

    %{job_id: job_id, runs: runs} = socket.assigns

    selected_run_id = get_run_id_for_job_id(job_id, runs)

    selected_run = runs |> Enum.find(&(&1.id == selected_run_id))

    socket
    |> assign(selected_run_id: selected_run_id, selected_run: selected_run)
    |> maybe_load_input_dataclip()
    |> maybe_load_output_dataclip()
  end

  defp get_run_id_for_job_id(job_id, runs) do
    runs
    |> Enum.find(%{}, &(&1.job_id == job_id))
    |> Map.get(:id)
  end
end
