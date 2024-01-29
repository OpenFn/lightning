defmodule LightningWeb.AttemptLive.Show do
  use LightningWeb, :live_view
  use LightningWeb.AttemptLive.Streaming, chunk_size: 100

  import LightningWeb.AttemptLive.Components

  alias Lightning.Projects
  alias LightningWeb.Components.Viewers
  alias Phoenix.LiveView.AsyncResult

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def render(assigns) do
    assigns =
      assigns |> assign(:no_step_selected?, is_nil(assigns.selected_step_id))

    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:title>
            <%= @page_title %>
            <span class="pl-2 font-light">
              <%= display_short_uuid(@id) %>
            </span>
          </:title>
        </LayoutComponents.header>
      </:header>

      <LayoutComponents.centered class="@container/main">
        <.async_result :let={attempt} assign={@attempt}>
          <:loading>
            <.loading_filler />
          </:loading>
          <:failed :let={_reason}>
            there was an error loading the run
          </:failed>

          <div class="flex gap-6 @5xl/main:flex-row flex-col">
            <div class="basis-1/3 flex-none flex gap-6 @5xl/main:flex-col flex-row">
              <.detail_list
                id={"attempt-detail-#{attempt.id}"}
                class="flex-1 @5xl/main:flex-none"
              >
                <.list_item>
                  <:label>Workflow</:label>
                  <:value>
                    <.link
                      navigate={~p"/projects/#{@project}/w/#{@workflow.id}"}
                      class="hover:underline hover:text-primary-900 whitespace-nowrap text-ellipsis"
                    >
                      <span class="whitespace-nowrap text-ellipsis">
                        <%= @workflow.name %>
                      </span>
                      <.icon name="hero-arrow-up-right" class="h-2 w-2 float-right" />
                    </.link>
                  </:value>
                </.list_item>
                <.list_item>
                  <:label>Work Order</:label>
                  <:value>
                    <.link
                      navigate={
                        ~p"/projects/#{@project}/history?#{%{filters: %{workorder_id: attempt.work_order_id}}}"
                      }
                      class="hover:underline hover:text-primary-900 whitespace-nowrap text-ellipsis"
                    >
                      <span class="whitespace-nowrap text-ellipsis">
                        <%= display_short_uuid(attempt.work_order_id) %>
                      </span>
                      <.icon name="hero-arrow-up-right" class="h-2 w-2 float-right" />
                    </.link>
                  </:value>
                </.list_item>
                <.list_item>
                  <:label>Started</:label>
                  <:value>
                    <%= if attempt.started_at,
                      do:
                        Timex.format!(
                          attempt.started_at,
                          "%d/%b/%y, %H:%M:%S",
                          :strftime
                        ) %>
                  </:value>
                </.list_item>
                <.list_item>
                  <:label>Finished</:label>
                  <:value>
                    <%= if attempt.finished_at,
                      do:
                        Timex.Format.DateTime.Formatters.Relative.format!(
                          attempt.finished_at,
                          "{relative}"
                        ) %>
                  </:value>
                </.list_item>
                <.list_item>
                  <:label>Duration</:label>
                  <:value>
                    <.elapsed_indicator attempt={attempt} />
                  </:value>
                </.list_item>
                <.list_item>
                  <:label>Status</:label>
                  <:value><.state_pill state={attempt.state} /></:value>
                </.list_item>
              </.detail_list>

              <.step_list
                :let={step}
                id={"step-list-#{attempt.id}"}
                steps={@steps}
                class="flex-1"
              >
                <.link patch={"?step=#{step.id}"} id={"select-step-#{step.id}"}>
                  <.step_item
                    step={step}
                    is_clone={
                      DateTime.compare(step.inserted_at, attempt.inserted_at) == :lt
                    }
                    selected={step.id == @selected_step_id}
                    show_inspector_link={true}
                    attempt_id={attempt.id}
                    project_id={@project}
                  />
                </.link>
              </.step_list>
            </div>
            <div class="basis-2/3 flex-none flex flex-col gap-4">
              <Common.tab_bar orientation="horizontal" id="1" default_hash="log">
                <Common.tab_item orientation="horizontal" hash="log">
                  <.icon
                    name="hero-command-line"
                    class="h-5 w-5 inline-block mr-1 align-middle"
                  />
                  <span class="inline-block align-middle">Log</span>
                </Common.tab_item>
                <Common.tab_item
                  orientation="horizontal"
                  hash="input"
                  disabled={@no_step_selected?}
                  disabled_msg="A valid step must be selected to view its input"
                >
                  <.icon
                    name="hero-arrow-down-on-square"
                    class="h-5 w-5 inline-block mr-1 align-middle"
                  />
                  <span class="inline-block align-middle">Input</span>
                </Common.tab_item>
                <Common.tab_item
                  orientation="horizontal"
                  hash="output"
                  disabled={@no_step_selected?}
                  disabled_msg="A valid step (with a readable output) must be selected to view its output"
                >
                  <.icon
                    name="hero-arrow-up-on-square"
                    class="h-5 w-5 inline-block mr-1 align-middle"
                  />
                  <span class="inline-block align-middle">
                    Output
                  </span>
                </Common.tab_item>
              </Common.tab_bar>

              <Common.panel_content for_hash="log">
                <Viewers.log_viewer
                  id={"attempt-log-#{attempt.id}"}
                  highlight_id={@selected_step_id}
                  stream={@streams.log_lines}
                />
              </Common.panel_content>
              <Common.panel_content for_hash="input">
                <Viewers.dataclip_viewer_for_zero_persistence
                  id={"step-input-#{@selected_step_id}"}
                  stream={@streams.input_dataclip}
                  step={@selected_step}
                  dataclip={
                    @input_dataclip && @input_dataclip.ok? && @input_dataclip.result
                  }
                  input_or_output={:input}
                  project_id={@project.id}
                  project_admins={@admin_contacts}
                  has_admin_access?={@can_edit_data_retention}
                />
              </Common.panel_content>
              <Common.panel_content for_hash="output">
                <Viewers.dataclip_viewer_for_zero_persistence
                  id={"step-output-#{@selected_step_id}"}
                  stream={@streams.output_dataclip}
                  step={@selected_step}
                  dataclip={
                    @output_dataclip && @output_dataclip.ok? &&
                      @output_dataclip.result
                  }
                  input_or_output={:output}
                  project_id={@project.id}
                  project_admins={@admin_contacts}
                  has_admin_access?={@can_edit_data_retention}
                />
              </Common.panel_content>
            </div>
          </div>
        </.async_result>
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    %{project_user: project_user, project: project} = socket.assigns

    {:ok,
     socket
     |> assign(
       active_menu_item: :runs,
       page_title: "Run",
       id: id,
       selected_step_id: nil,
       steps: []
     )
     |> stream(:log_lines, [])
     |> stream(:input_dataclip, [])
     |> assign(:input_dataclip, false)
     |> stream(:output_dataclip, [])
     |> assign(:output_dataclip, false)
     |> assign(:attempt, AsyncResult.loading())
     |> assign(:log_lines, AsyncResult.loading())
     |> assign(can_edit_data_retention: project_user.role in [:owner, :admin])
     |> assign(admin_contacts: Projects.list_project_admin_emails(project.id))
     |> get_attempt_async(id)}
  end

  def handle_steps_change(socket) do
    %{selected_step_id: selected_step_id, steps: steps} = socket.assigns

    selected_step =
      steps
      |> Enum.find(&(&1.id == selected_step_id))

    socket
    |> assign(selected_step: selected_step)
    |> maybe_load_input_dataclip()
    |> maybe_load_output_dataclip()
  end

  @impl true
  def handle_params(params, _, socket) do
    selected_step_id = Map.get(params, "step")

    {:noreply, socket |> apply_selected_step_id(selected_step_id)}
  end
end
