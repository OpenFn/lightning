defmodule LightningWeb.RunLive.RunViewerLive do
  use LightningWeb, {:live_view, container: {:div, []}}
  use LightningWeb.RunLive.Streaming, chunk_size: 100

  import LightningWeb.RunLive.Components

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias LightningWeb.Components.Tabbed
  alias LightningWeb.Components.Viewers
  alias LightningWeb.WorkflowLive.Helpers

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
          <div class="grow flex flex-col gap-4 min-h-0">
            <Tabbed.panels id="run-viewer-panels" class="contents" default_hash="run">
              <:panel hash="run" class="overflow-auto">
                <.detail_list id={"run-detail-#{run.id}"}>
                  <.list_item>
                    <:label class="whitespace-nowrap">Work Order</:label>
                    <:value>
                      <.link
                        navigate={
                          ~p"/projects/#{@project}/history?#{%{filters: %{workorder_id: run.work_order_id}}}"
                        }
                        class="link-uuid"
                      >
                        {display_short_uuid(run.work_order_id)}
                      </.link>
                    </:value>
                  </.list_item>
                  <.list_item>
                    <:label>Run</:label>
                    <:value>
                      <.link
                        patch={
                          ~p"/projects/#{@project}/runs/#{run}?step=#{@selected_step_id || ""}"
                        }
                        class="link-uuid"
                      >
                        {display_short_uuid(run.id)}
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
                    <:label>Duration</:label>
                    <:value>
                      <.elapsed_indicator item={run} context="viewer" />
                    </:value>
                  </.list_item>
                  <.list_item>
                    <:label>Status</:label>
                    <:value><.state_pill state={run.state} /></:value>
                  </.list_item>
                  <.list_item>
                    <:label>Steps:</:label>
                  </.list_item>
                </.detail_list>
                <.step_list
                  :let={step}
                  id={"run-tab-step-list-#{run.id}"}
                  steps={@steps}
                  class="flex-1 items-center ml-2"
                >
                  <.step_item
                    step={step}
                    workflow_version={@workflow.lock_version}
                    run_id={run.id}
                    job_id={@job_id}
                    is_clone={
                      DateTime.compare(step.inserted_at, run.inserted_at) == :lt
                    }
                    phx-click="select_step"
                    phx-value-id={step.id}
                    selected={step.id == @selected_step_id}
                    class="cursor-pointer"
                    project_id={@project}
                    context="run-tab"
                  />
                </.step_list>
              </:panel>
              <:panel hash="log" class="h-full mb-2">
                <div class="flex flex-col h-full @5xl/viewer:flex-row">
                  <div class="z-50 min-h-0 max-h-[30%] 0 mb-1 overflow-auto flex-none flex @5xl/viewer:flex-row flex-col @5xl/viewer:max-h-[100%]">
                    <.step_list
                      :let={step}
                      id={"log-tab-step-list-#{run.id}"}
                      steps={@steps}
                      class=""
                    >
                      <.step_item
                        step={step}
                        workflow_version={@workflow.lock_version}
                        run_id={run.id}
                        job_id={@job_id}
                        is_clone={
                          DateTime.compare(step.inserted_at, run.inserted_at) == :lt
                        }
                        phx-click="select_step"
                        phx-value-id={step.id}
                        selected={step.id == @selected_step_id}
                        class="cursor-pointer"
                        project_id={@project}
                        context="log-tab"
                      />
                    </.step_list>
                  </div>

                  <div class="flex min-h-0 h-full grow bg-slate-700 overflow-auto rounded-md">
                    <Viewers.log_viewer
                      id={"run-log-#{run.id}"}
                      run_id={run.id}
                      run_state={@run.result.state}
                      logs_empty?={@log_lines_empty?}
                      selected_step_id={@selected_step_id}
                      current_user={@current_user}
                    />
                  </div>
                </div>
              </:panel>
              <:panel hash="input" class="grow overflow-auto">
                <%= if @run.ok? && @run.result.state in Lightning.Run.final_states() && is_nil(@selected_step_id) do %>
                  <div class="border-2 border-gray-200 border-dashed rounded-lg px-8 pt-6 pb-8 mb-4 flex flex-col">
                    <p class="text-sm text-center">
                      No input/output available. This step was never started.
                    </p>
                  </div>
                <% else %>
                  <div class="flex flex-col h-full @5xl/viewer:flex-row">
                    <div class="z-50 min-h-0 max-h-[30%] 0 mb-2 overflow-auto flex-none flex @5xl/viewer:flex-row flex-col @5xl/viewer:max-h-[100%]">
                      <.step_list
                        :let={step}
                        id={"input-tab-step-list-#{run.id}"}
                        steps={@steps}
                        class=""
                      >
                        <.step_item
                          step={step}
                          workflow_version={@workflow.lock_version}
                          run_id={run.id}
                          job_id={@job_id}
                          is_clone={
                            DateTime.compare(step.inserted_at, run.inserted_at) ==
                              :lt
                          }
                          phx-click="select_step"
                          phx-value-id={step.id}
                          selected={step.id == @selected_step_id}
                          class="cursor-pointer"
                          project_id={@project}
                          context="input-tab"
                        />
                      </.step_list>
                    </div>

                    <div class="flex-1 grow inset-0 overflow-auto rounded-md">
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
                    </div>
                  </div>
                <% end %>
              </:panel>
              <:panel hash="output" class="grow overflow-auto">
                <%= if @run.ok? && @run.result.state in Lightning.Run.final_states() && is_nil(@selected_step_id) do %>
                  <div class="border-2 border-gray-200 border-dashed rounded-lg px-8 pt-6 pb-8 mb-4 flex flex-col">
                    <p class="text-sm text-center">
                      No input/output available. This step was never started.
                    </p>
                  </div>
                <% else %>
                  <div class="flex flex-col h-full @5xl/viewer:flex-row">
                    <div class="z-50 min-h-0 max-h-[30%] 0 mb-2 overflow-auto flex-none flex @5xl/viewer:flex-row flex-col @5xl/viewer:max-h-[100%]">
                      <.step_list
                        :let={step}
                        id={"output-tab-step-list-#{run.id}"}
                        steps={@steps}
                        class=""
                      >
                        <.step_item
                          step={step}
                          workflow_version={@workflow.lock_version}
                          run_id={run.id}
                          job_id={@job_id}
                          is_clone={
                            DateTime.compare(step.inserted_at, run.inserted_at) ==
                              :lt
                          }
                          phx-click="select_step"
                          phx-value-id={step.id}
                          selected={step.id == @selected_step_id}
                          class="cursor-pointer"
                          project_id={@project}
                          context="output-tab"
                        />
                      </.step_list>
                    </div>

                    <div class="flex-1 grow inset-0 overflow-auto rounded-md">
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
                    </div>
                  </div>
                <% end %>
              </:panel>
            </Tabbed.panels>
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
          "user_id" => user_id,
          "socket_id" => socket_id
        } = session,
        socket
      ) do
    if connected?(socket) do
      Helpers.subscribe_to_params_update(socket_id)
    end

    project_user =
      Projects.get_project_user(%Project{id: project_id}, %User{id: user_id})

    {:ok,
     socket
     |> assign(
       selected_step_id: nil,
       job_id: Map.get(session, "job_id"),
       selected_step: nil,
       steps: [],
       current_user: Accounts.get_user(user_id)
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

  @impl true
  def handle_info({:updated_params, %{job_id: job_id}}, socket) do
    {:noreply, socket |> assign(job_id: job_id) |> handle_steps_change()}
  end

  def handle_steps_change(socket) do
    # either a job_id or a step_id is passed in
    # if a step_id is passed in, we can highlight the log lines immediately
    # if a job_id is passed in, we need to wait for the step to start
    # if neither is passed in, we can't highlight anything
    cond do
      changed?(socket, :selected_step_id) ->
        socket

      changed?(socket, :job_id) ->
        socket
        |> assign(
          :selected_step_id,
          get_step_id_for_job_id(socket.assigns.job_id, socket.assigns.steps)
        )

      true ->
        socket
        |> update(:selected_step_id, fn selected_step_id,
                                        %{job_id: job_id, steps: steps} ->
          selected_step_id || get_step_id_for_job_id(job_id, steps)
        end)
    end
    |> update(:selected_step, fn _, assigns ->
      Enum.find(assigns.steps, &(&1.id == assigns.selected_step_id))
    end)
    |> maybe_load_input_dataclip()
    |> maybe_load_output_dataclip()
  end

  defp get_step_id_for_job_id(job_id, steps) do
    steps
    |> Enum.find(%{}, &(&1.job_id == job_id))
    |> Map.get(:id)
  end
end
