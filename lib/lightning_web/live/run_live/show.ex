defmodule LightningWeb.RunLive.Show do
  use LightningWeb, :live_view
  use LightningWeb.RunLive.Streaming, chunk_size: 100

  import LightningWeb.Components.Icons
  import LightningWeb.RunLive.Components

  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects
  alias LightningWeb.Components.Tabbed
  alias LightningWeb.Components.Viewers
  alias Phoenix.LiveView.AsyncResult

  on_mount {LightningWeb.Hooks, :project_scope}
  on_mount {LightningWeb.Hooks, :check_limits}

  attr :run, :map, required: true
  attr :workflow, :map, required: true

  defp snapshot_version(assigns) do
    %{run: run, workflow: workflow} = assigns

    snapshot_version =
      if run.snapshot.lock_version == workflow.lock_version do
        "latest"
      else
        String.slice(run.snapshot.id, 0..6)
      end

    assigns =
      assign(assigns, snapshot_version: snapshot_version)

    ~H"""
    <LightningWeb.Components.Common.snapshot_version_chip
      id="run-workflow-version"
      version={@snapshot_version}
      tooltip={
        if @snapshot_version == "latest",
          do: "This run is based on the latest version of this workflow.",
          else:
            "This run is based on a snapshot of this workflow that was taken on #{Lightning.Helpers.format_date(run.snapshot.inserted_at, "%F at %T")}"
      }
    />
    """
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns |> assign(:no_step_selected?, is_nil(assigns.selected_step_id))

    ~H"""
    <LayoutComponents.page_content>
      <:banner>
        <Common.dynamic_component
          :if={assigns[:banner]}
          function={@banner.function}
          args={@banner.attrs}
        />
      </:banner>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:breadcrumbs>
            <LayoutComponents.breadcrumbs>
              <LayoutComponents.breadcrumb_project_picker label={@project.name} />
              <LayoutComponents.breadcrumb_items items={[{"History", ~p"/projects/#{@project}/history"}]} />
              <LayoutComponents.breadcrumb show_separator={true}>
                <:label>
                  {@page_title}
                  <span class="pl-2 font-light">
                    {display_short_uuid(@id)}
                  </span>
                  <div class="mx-2"></div>
                  <.async_result :let={run} assign={@run}>
                    <%= if run do %>
                      <.snapshot_version run={run} workflow={@workflow} />
                    <% end %>
                  </.async_result>
                </:label>
              </LayoutComponents.breadcrumb>
            </LayoutComponents.breadcrumbs>
          </:breadcrumbs>
        </LayoutComponents.header>
      </:header>

      <LayoutComponents.centered class="@container/main h-full">
        <.async_result :let={run} assign={@run}>
          <:loading>
            <.loading_filler />
          </:loading>
          <:failed :let={_reason}>
            there was an error loading the run
          </:failed>
          <div class="flex gap-x-6 @5xl/main:flex-row flex-col h-full">
            <div class="@5xl/main:basis-1/3 flex gap-y-6 @5xl/main:flex-col flex-row">
              <.detail_list
                id={"run-detail-#{run.id}"}
                class="flex-1 @5xl/main:flex-none"
              >
                <.list_item>
                  <:label>Workflow</:label>
                  <:value>
                    <.link
                      navigate={
                        # Only include version param if snapshot differs from current workflow version
                        if run.snapshot.lock_version == @workflow.lock_version do
                          ~p"/projects/#{@project}/w/#{@workflow.id}?a=#{run.id}"
                        else
                          ~p"/projects/#{@project}/w/#{@workflow.id}?a=#{run.id}&v=#{run.snapshot.lock_version}"
                        end
                      }
                      class="link text-ellipsis"
                    >
                      {@workflow.name}
                    </.link>
                  </:value>
                </.list_item>
                <.list_item>
                  <:label>Work Order</:label>
                  <:value>
                    <.link
                      navigate={
                        ~p"/projects/#{@project}/history?#{%{filters: %{workorder_id: run.work_order_id}}}"
                      }
                      class="link font-mono"
                    >
                      {display_short_uuid(run.work_order_id)}
                    </.link>
                  </:value>
                </.list_item>
                <%= if run.created_by || run.starting_trigger do %>
                  <.list_item>
                    <:label>Started by</:label>
                    <:value>
                      <%= cond do %>
                        <% run.created_by -> %>
                          {run.created_by.email}
                        <% run.starting_trigger -> %>
                          {String.capitalize(
                            Atom.to_string(run.starting_trigger.type)
                          )} trigger
                        <% true -> %>
                      <% end %>
                    </:value>
                  </.list_item>
                <% end %>
                <.list_item>
                  <:label>Started</:label>
                  <:value>
                    <%= if run.started_at do %>
                      <Common.datetime datetime={run.started_at} />
                    <% end %>
                  </:value>
                </.list_item>
                <.list_item>
                  <:label>Finished</:label>
                  <:value>
                    <%= if run.finished_at do %>
                      <Common.datetime datetime={run.finished_at} />
                    <% end %>
                  </:value>
                </.list_item>
                <.list_item>
                  <:label>Duration</:label>
                  <:value>
                    <.elapsed_indicator item={run} context="show" />
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
                class="flex-1 items-center"
              >
                <.link patch={"?step=#{step.id}"}>
                  <.step_item
                    step={step}
                    workflow_version={@workflow.lock_version}
                    is_clone={
                      DateTime.compare(step.inserted_at, run.inserted_at) == :lt
                    }
                    selected={step.id == @selected_step_id}
                    run_id={run.id}
                    project_id={@project}
                  />
                </.link>
              </.step_list>
            </div>
            <div class="@5xl/main:basis-2/3 flex flex-col gap-4 h-full">
              <Tabbed.container
                id={"run-#{run.id}-tabbed-container"}
                class="run-tab-container"
                default_hash="log"
              >
                <:tab hash="log">
                  <.icon
                    name="hero-command-line"
                    class="h-5 w-5 inline-block mr-1 align-middle"
                  />
                  <span class="inline-block align-middle">Log</span>
                </:tab>
                <:tab
                  hash="input"
                  disabled={@no_step_selected?}
                  disabled_msg="A valid step must be selected to view its input"
                >
                  <.icon
                    name="hero-arrow-down-on-square"
                    class="h-5 w-5 inline-block mr-1 align-middle"
                  />
                  <span class="inline-block align-middle">Input</span>
                </:tab>
                <:tab
                  hash="output"
                  disabled={@no_step_selected?}
                  disabled_msg="A valid step (with a readable output) must be selected to view its output"
                >
                  <.icon
                    name="hero-arrow-up-on-square"
                    class="h-5 w-5 inline-block mr-1 align-middle rotate-180"
                  />
                  <span class="inline-block align-middle"> Output </span>
                </:tab>
                <:panel hash="input" class="flex-grow h-full">
                  <Viewers.step_dataclip_viewer
                    id={"step-input-#{@selected_step_id}"}
                    run_state={@run.result.state}
                    step={@selected_step}
                    dataclip={@input_dataclip}
                    input_or_output={:input}
                    project_id={@project.id}
                    admin_contacts={@admin_contacts}
                    can_edit_data_retention={@can_edit_data_retention}
                  />
                </:panel>
                <:panel hash="log" class="flex h-full">
                  <Viewers.log_viewer
                    id={"run-log-#{run.id}"}
                    class="h-full"
                    run_id={run.id}
                    run_state={@run.result.state}
                    logs_empty?={@log_lines_empty?}
                    selected_step_id={@selected_step_id}
                    current_user={@current_user}
                  />
                </:panel>
                <:panel hash="output" class="flex-1">
                  <Viewers.step_dataclip_viewer
                    id={"step-output-#{@selected_step_id}"}
                    run_state={@run.result.state}
                    step={@selected_step}
                    dataclip={@output_dataclip}
                    input_or_output={:output}
                    project_id={@project.id}
                    admin_contacts={@admin_contacts}
                    can_edit_data_retention={@can_edit_data_retention}
                  />
                </:panel>
              </Tabbed.container>
            </div>
          </div>
        </.async_result>
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    %{current_user: user, project_user: project_user, project: project} =
      socket.assigns

    {:ok,
     socket
     |> assign(
       active_menu_item: :runs,
       page_title: "Run",
       id: id,
       selected_step_id: nil,
       steps: []
     )
     |> assign(:input_dataclip, nil)
     |> assign(:output_dataclip, nil)
     |> assign(:run, AsyncResult.loading())
     |> assign(:log_lines, AsyncResult.loading())
     |> assign(:log_lines_empty?, true)
     |> assign(
       can_edit_data_retention:
         Permissions.can?(
           ProjectUsers,
           :edit_data_retention,
           user,
           project_user
         )
     )
     |> assign(admin_contacts: Projects.list_project_admin_emails(project.id))
     |> get_run_async(id)}
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

  @impl true
  def handle_info(%Lightning.Runs.Events.DataclipUpdated{}, socket) do
    {:noreply, socket}
  end
end
