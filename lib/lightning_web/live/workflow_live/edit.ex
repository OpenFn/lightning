defmodule LightningWeb.WorkflowLive.Edit do
  @moduledoc false
  use LightningWeb, {:live_view, container: {:div, []}}

  import LightningWeb.Components.NewInputs
  import LightningWeb.Components.Icons
  import LightningWeb.WorkflowLive.Components

  alias Lightning.AiAssistant
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Invocation
  alias Lightning.OauthClients
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects
  alias Lightning.Runs
  alias Lightning.Runs.Events.DataclipUpdated
  alias Lightning.Runs.Events.RunUpdated
  alias Lightning.Runs.Events.StepCompleted
  alias Lightning.Services.UsageLimiter
  alias Lightning.Workflows
  alias Lightning.Workflows.Events.WorkflowUpdated
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Presence
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkOrders
  alias LightningWeb.WorkflowLive.Helpers
  alias LightningWeb.WorkflowNewLive.WorkflowParams
  alias Phoenix.LiveView.JS

  require Lightning.Run

  on_mount {LightningWeb.Hooks, :project_scope}

  attr :changeset, :map, required: true
  attr :project_user, :map, required: true

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(
        base_url:
          case assigns.live_action do
            :new ->
              ~p"/projects/#{assigns.project}/w/new"

            :edit ->
              ~p"/projects/#{assigns.project}/w/#{assigns.workflow}"
          end,
        workflow_form: to_form(assigns.changeset),
        save_and_run_disabled: save_and_run_disabled?(assigns),
        display_banner:
          !assigns.has_presence_edit_priority &&
            assigns.current_user.id not in assigns.view_only_users_ids &&
            assigns.snapshot_version_tag == "latest",
        banner_message:
          banner_message(
            assigns.current_user_presence,
            assigns.prior_user_presence
          )
      )

    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header
          current_user={@current_user}
          project={@project}
          breadcrumbs={[{"Workflows", "/projects/#{@project.id}/w"}]}
        >
          <:title>
            <%= @page_title %>
            <div class="mx-2"></div>
            <LightningWeb.Components.Common.snapshot_version_chip
              id="canvas-workflow-version"
              version={@snapshot_version_tag}
              tooltip={
                if @snapshot_version_tag == "latest",
                  do: "This is the latest version of this workflow",
                  else:
                    "You are viewing a snapshot of this workflow that was taken on #{Lightning.Helpers.format_date(@snapshot.inserted_at)}"
              }
            />
            <LightningWeb.WorkflowLive.Components.online_users
              id="canvas-online-users"
              presences={@presences}
              current_user={@current_user}
              prior_user={@prior_user_presence.user}
              class="mr-2"
            />
            <div :if={@snapshot_version_tag != "latest" && @can_edit_workflow}>
              <span
                id="edit-disabled-warning"
                class="cursor-pointer text-xs flex items-center"
                phx-hook="Tooltip"
                data-placement="bottom"
                aria-label="You cannot edit or run an old snapshot of a workflow"
              >
                <.icon
                  name="hero-information-circle-solid"
                  class="h-4 w-4 text-primary-600 opacity-50"
                /> Read-only
              </span>
            </div>
          </:title>

          <.button
            :if={@snapshot_version_tag != "latest"}
            id={"version-switcher-button-#{@workflow.id}"}
            type="button"
            phx-click="switch-version"
            phx-value-type="commit"
            color_class="text-white bg-primary-600 hover:bg-primary-700 disabled:bg-primary-300"
          >
            Switch to latest version
          </.button>
          <.with_changes_indicator
            :if={@snapshot_version_tag == "latest"}
            changeset={@changeset}
          >
            <div class="flex flex-row gap-2">
              <.icon
                :if={!@can_edit_workflow}
                name="hero-lock-closed"
                class="w-5 h-5 place-self-center text-gray-300"
              />
              <div class="flex flex-row m-auto gap-2">
                <div>
                  <.link
                    patch={
                      if @selection_mode == "settings",
                        do: @base_url,
                        else: "#{@base_url}?m=settings"
                    }
                    class="w-5 h-5 place-self-center text-slate-500 hover:text-slate-400 cursor-pointer"
                    id="toggle-settings"
                  >
                    <.icon name="hero-adjustments-vertical" />
                  </.link>
                </div>
                <.offline_indicator />
              </div>
              <.save_workflow_button
                id="top-bar-save-workflow-btn"
                changeset={@changeset}
                can_edit_workflow={@can_edit_workflow}
                snapshot_version_tag={@snapshot_version_tag}
                has_presence_priority={@has_presence_edit_priority}
              />
            </div>
          </.with_changes_indicator>
        </LayoutComponents.header>
      </:header>

      <div class="relative h-full flex" id={"workflow-edit-#{@workflow.id}"}>
        <%!-- Job Edit View --%>
        <div class="flex-none" id="job-editor-pane">
          <div
            :if={@selected_job && @selection_mode == "expand"}
            class={[
              "fixed left-0 top-0 right-0 bottom-0 flex-wrap",
              "hidden opacity-0",
              "bg-white inset-0 z-30 overflow-hidden drop-shadow-[0_35px_35px_rgba(0,0,0,0.25)]"
            ]}
            phx-mounted={fade_in()}
            phx-remove={fade_out()}
          >
            <LightningWeb.WorkflowLive.JobView.job_edit_view
              job={@selected_job}
              snapshot={@snapshot}
              snapshot_version={@snapshot_version_tag}
              current_user={@current_user}
              display_banner={@display_banner}
              banner_message={@banner_message}
              presences={@presences}
              prior_user_presence={@prior_user_presence}
              project={@project}
              socket={@socket}
              follow_run_id={@follow_run && @follow_run.id}
              close_url={close_url(assigns, :selected_job, :select)}
              form={single_inputs_for(@workflow_form, :jobs, @selected_job.id)}
            >
              <.collapsible_panel
                id={"manual-job-#{@selected_job.id}"}
                class="h-full border border-l-0 manual-job-panel"
              >
                <:tabs>
                  <LightningWeb.Components.Tabbed.tabs
                    id="tab-bar-left"
                    default_hash="manual"
                    class="flex flex-row space-x-6 -my-2 job-viewer-tabs"
                  >
                    <:tab hash="manual">
                      <span class="inline-block align-middle">Input</span>
                    </:tab>
                    <:tab
                      :if={Lightning.AiAssistant.available?(@current_user)}
                      hash="aichat"
                    >
                      <span class="inline-block align-middle">AI Assistant</span>
                    </:tab>
                  </LightningWeb.Components.Tabbed.tabs>
                </:tabs>
                <LightningWeb.Components.Tabbed.panels
                  id="input-panels"
                  class="contents"
                  default_hash="manual"
                >
                  <:panel hash="manual" class="overflow-auto h-full">
                    <div class="grow flex flex-col gap-4 p-2 min-h-0 h-full">
                      <LightningWeb.WorkflowLive.ManualWorkorder.component
                        id={"manual-job-#{@selected_job.id}"}
                        form={@manual_run_form}
                        dataclips={@selectable_dataclips}
                        disabled={
                          !@can_run_workflow ||
                            @snapshot_version_tag != "latest"
                        }
                        project={@project}
                        admin_contacts={@admin_contacts}
                        can_edit_data_retention={@can_edit_data_retention}
                        follow_run={@follow_run}
                        step={@step}
                        show_missing_dataclip_selector={
                          @show_missing_dataclip_selector
                        }
                      />
                    </div>
                  </:panel>
                  <:panel
                    :if={Lightning.AiAssistant.available?(@current_user)}
                    hash="aichat"
                    class="h-full"
                  >
                    <%= if @ai_assistant_enabled do %>
                      <div class="grow min-h-0 h-full text-sm">
                        <.live_component
                          module={LightningWeb.WorkflowLive.AiAssistantComponent}
                          can_edit_workflow={@can_edit_workflow}
                          project_id={@project.id}
                          project_has_chat_sessions={@project_has_chat_sessions}
                          current_user={@current_user}
                          selected_job={@selected_job}
                          chat_session_id={@chat_session_id}
                          query_params={@query_params}
                          base_url={@base_url}
                          action={if(@chat_session_id, do: :show, else: :new)}
                          id={"aichat-#{@selected_job.id}"}
                        />
                      </div>
                    <% else %>
                      <div class="flex flex-col items-center justify-center h-full">
                        <div class="text-center w-1/2">
                          <p class="text-gray-500 text-sm mb-2">
                            AI Assistant has not been configured for your instance - contact your admin for support.
                          </p>
                          <p class="text-gray-500 text-sm mb-2">
                            Try the AI Assistant on Openfn cloud for free at
                            <a
                              href="https://app.openfn.org"
                              target="_blank"
                              class="text-primary-600"
                            >
                              app.openfn.org
                            </a>
                          </p>
                        </div>
                      </div>
                    <% end %>
                  </:panel>
                </LightningWeb.Components.Tabbed.panels>
              </.collapsible_panel>
              <:footer>
                <div class="flex flex-row gap-x-2">
                  <% {is_empty, error_message} =
                    editor_is_empty(@workflow_form, @selected_job) %>

                  <div
                    :if={@snapshot_version_tag == "latest" && @display_banner}
                    id={"inspector-banner-#{@current_user.id}"}
                    class="flex items-center text-sm font-medium text-gray-500"
                  >
                    <span
                      id={"inspector-banner-#{@current_user.id}-tooltip"}
                      class="cursor-pointer text-xs flex items-center"
                      phx-hook="Tooltip"
                      data-placement="top"
                      aria-label={@banner_message}
                    >
                      <.icon name="hero-lock-closed-solid" class="h-4 w-4" />
                      Read-only
                    </span>
                  </div>

                  <.version_switcher_toggle
                    :if={display_switcher(@snapshot, @workflow)}
                    id={@selected_job.id}
                    label="Latest Version"
                    disabled={job_deleted?(@selected_job, @workflow)}
                    version={@snapshot_version_tag}
                  />

                  <.save_is_blocked_error :if={is_empty}>
                    <%= error_message %>
                  </.save_is_blocked_error>

                  <.icon
                    :if={!@can_edit_workflow}
                    name="hero-lock-closed"
                    class="w-5 h-5 place-self-center text-gray-300"
                  />
                  <.run_buttons
                    step={@step}
                    manual_run_form={@manual_run_form}
                    selectable_dataclips={@selectable_dataclips}
                    follow_run={@follow_run}
                    save_and_run_disabled={@save_and_run_disabled}
                    snapshot_version_tag={@snapshot_version_tag}
                  />
                  <.with_changes_indicator changeset={@changeset}>
                    <.save_workflow_button
                      id="inspector-save-workflow-btn"
                      changeset={@changeset}
                      can_edit_workflow={@can_edit_workflow}
                      snapshot_version_tag={@snapshot_version_tag}
                      has_presence_priority={@has_presence_edit_priority}
                    />
                  </.with_changes_indicator>
                </div>
              </:footer>
            </LightningWeb.WorkflowLive.JobView.job_edit_view>
          </div>
        </div>

        <div
          phx-hook="WorkflowEditor"
          class="grow"
          id={"editor-#{@workflow.id}"}
          phx-update="ignore"
        >
          <%!-- Before Editor component has mounted --%>
          <div class="flex place-content-center h-full cursor-wait">
            <span class="inline-block top-[50%] relative">
              <div class="flex items-center justify-center">
                <.button_loader>
                  Loading workflow
                </.button_loader>
              </div>
            </span>
          </div>
        </div>
        <.live_component
          :if={@selected_job}
          id="new-credential-modal"
          module={LightningWeb.CredentialLive.CredentialFormComponent}
          action={:new}
          credential_type={@selected_credential_type}
          credential={
            %Lightning.Credentials.Credential{
              user_id: @current_user.id,
              project_credentials: [
                %Lightning.Projects.ProjectCredential{
                  project_id: @project.id
                }
              ]
            }
          }
          current_user={@current_user}
          oauth_clients={@oauth_clients}
          projects={[]}
          project={@project}
          show_project_credentials={false}
          on_save={
            fn credential ->
              form =
                single_inputs_for(@workflow_form, :jobs, @selected_job.id)

              params =
                LightningWeb.Utils.build_params_for_field(
                  form,
                  :project_credential_id,
                  credential.project_credentials |> Enum.at(0) |> Map.get(:id)
                )

              send_form_changed(params)
            end
          }
          can_create_project_credential={@can_edit_workflow}
          return_to={
            ~p"/projects/#{@project.id}/w/#{@workflow.id}?s=#{@selected_job.id}"
          }
        />
        <Common.banner
          :if={@display_banner}
          type="warning"
          id={"canvas-banner-#{@current_user.id}"}
          message={@banner_message}
          class="absolute"
          icon
          centered
        />
        <.form
          id="workflow-form"
          for={@workflow_form}
          phx-submit="save"
          phx-hook="SaveViaCtrlS"
          phx-change="validate"
        >
          <input type="hidden" name="_ignore_me" />
          <.panel
            :if={@selection_mode == "settings"}
            title="Workflow settings"
            id={"workflow-settings-#{@workflow.id}"}
            class="hidden"
            phx-mounted={fade_in()}
            phx-remove={fade_out()}
            cancel_url={@base_url}
          >
            <.workflow_settings form={@workflow_form} />
          </.panel>

          <.single_inputs_for
            :let={{jf}}
            :if={@selected_job}
            form={@workflow_form}
            field={:jobs}
            id={@selected_job.id}
          >
            <.panel
              title={
                jf[:name].value
                |> then(fn
                  "" -> "Untitled Job"
                  name -> name
                end)
              }
              id={"job-pane-#{@selected_job.id}"}
              cancel_url={close_url(assigns, :selected_job, :unselect)}
              class="hidden"
              phx-mounted={fade_in()}
              phx-remove={fade_out()}
            >
              <!-- Show only the currently selected one -->
              <.job_form
                on_change={&send_form_changed/1}
                editable={
                  is_nil(@workflow.deleted_at) && @can_edit_workflow &&
                    @snapshot_version_tag == "latest" &&
                    @has_presence_edit_priority
                }
                form={jf}
                project_user={@project_user}
              />
              <:footer>
                <div class="flex flex-row">
                  <div class="flex items-center">
                    <.expand_job_editor
                      base_url={@base_url}
                      snapshot_lock_version={@snapshot && @snapshot.lock_version}
                      job={@selected_job}
                      selected_run={@selected_run}
                      form={@workflow_form}
                    />
                  </div>
                  <div class="grow flex justify-end">
                    <label>
                      <.button
                        id="delete-job-button"
                        phx-click="delete_node"
                        phx-value-id={@selected_job.id}
                        class="focus:ring-red-500 bg-red-600 hover:bg-red-700 disabled:bg-red-300"
                        disabled={
                          !is_nil(@workflow.deleted_at) or !@can_edit_workflow or
                            @has_child_edges or @is_first_job or
                            @snapshot_version_tag != "latest" ||
                            !@has_presence_edit_priority
                        }
                        tooltip={
                          job_deletion_tooltip_message(
                            is_struct(@workflow.deleted_at),
                            @can_edit_workflow,
                            @has_child_edges,
                            @is_first_job
                          )
                        }
                        data-confirm="Are you sure you want to delete this step?"
                      >
                        Delete Step
                      </.button>
                    </label>
                  </div>
                </div>
              </:footer>
            </.panel>
          </.single_inputs_for>
          <.single_inputs_for
            :let={tf}
            :if={@selected_trigger}
            form={@workflow_form}
            field={:triggers}
            id={@selected_trigger.id}
          >
            <.panel
              id={"trigger-pane-#{@selected_trigger.id}"}
              cancel_url={close_url(assigns, :selected_trigger, :unselect)}
              class="hidden"
              phx-mounted={fade_in()}
              phx-remove={fade_out()}
              title={
                Phoenix.HTML.Form.input_value(tf, :type)
                |> to_string()
                |> then(fn
                  "" -> "New Trigger"
                  "webhook" -> "Webhook Trigger"
                  "cron" -> "Cron Trigger"
                  # TODO Not tested
                  "kafka" -> "Kafka Trigger"
                end)
              }
            >
              <div class="w-auto h-full" id={"trigger-pane-#{@workflow.id}"}>
                <!-- Show only the currently selected one -->
                <.trigger_form
                  form={tf}
                  on_change={&send_form_changed/1}
                  disabled={
                    !is_nil(@workflow.deleted_at) or !@can_edit_workflow or
                      @snapshot_version_tag != "latest" ||
                      !@has_presence_edit_priority
                  }
                  can_write_webhook_auth_method={@can_write_webhook_auth_method}
                  selected_trigger={@selected_trigger}
                  action={@live_action}
                  cancel_url={close_url(assigns, :selected_trigger, :unselect)}
                />
              </div>
            </.panel>
          </.single_inputs_for>
          <.single_inputs_for
            :let={ef}
            :if={@selected_edge}
            form={@workflow_form}
            field={:edges}
            id={@selected_edge.id}
          >
            <.panel
              id={"edge-pane-#{@selected_edge.id}"}
              cancel_url={close_url(assigns, :selected_edge, :unselect)}
              title="Path"
              class="hidden"
              phx-mounted={fade_in()}
              phx-remove={fade_out()}
            >
              <div class="w-auto h-full" id={"edge-pane-#{@workflow.id}"}>
                <!-- Show only the currently selected one -->
                <.edge_form
                  form={ef}
                  disabled={
                    !is_nil(@workflow.deleted_at) or !@can_edit_workflow or
                      @snapshot_version_tag != "latest" ||
                      !@has_presence_edit_priority
                  }
                  cancel_url={close_url(assigns, :selected_edge, :unselect)}
                />
              </div>
            </.panel>
          </.single_inputs_for>
        </.form>

        <.live_component
          :if={
            @live_action == :edit && @can_write_webhook_auth_method &&
              @selected_trigger && @snapshot_version_tag == "latest"
          }
          module={LightningWeb.WorkflowLive.WebhookAuthMethodModalComponent}
          id="webhooks_auth_method_modal"
          action={:new}
          trigger={@selected_trigger}
          project={@project}
          current_user={@current_user}
          return_to={
            ~p"/projects/#{@project.id}/w/#{@workflow.id}?#{%{s: @selected_trigger.id}}"
          }
        />
      </div>
    </LayoutComponents.page_content>
    """
  end

  def run_buttons(assigns) do
    ~H"""
    <div id="run-buttons" class="inline-flex rounded-md shadow-sm">
      <.save_and_run_button {assigns} />
      <.create_new_work_order_dropdown
        :if={step_retryable?(@step, @manual_run_form, @selectable_dataclips)}
        {assigns}
      />
    </div>
    """
  end

  defp save_and_run_button(assigns) do
    ~H"""
    <.button
      id="save-and-run"
      phx-hook="DefaultRunViaCtrlEnter"
      {save_and_run_attributes(assigns)}
      class={save_and_run_classes(assigns)}
      disabled={
        assigns.save_and_run_disabled ||
          processing(assigns.follow_run) ||
          selected_dataclip_wiped?(
            assigns.manual_run_form,
            assigns.selectable_dataclips
          ) ||
          assigns.snapshot_version_tag != "latest"
      }
    >
      <%= if processing(@follow_run) do %>
        <.icon name="hero-arrow-path" class="w-4 h-4 animate-spin mr-1" /> Processing
      <% else %>
        <%= if step_retryable?(@step, @manual_run_form, @selectable_dataclips) do %>
          <.icon name="hero-play-mini" class="w-4 h-4 mr-1" /> Retry from here
        <% else %>
          <.icon name="hero-play-mini" class="w-4 h-4 mr-1" /> Create New Work Order
        <% end %>
      <% end %>
    </.button>
    """
  end

  defp save_and_run_attributes(assigns) do
    if step_retryable?(assigns) do
      [
        type: "button",
        "phx-click": "rerun",
        "phx-value-run_id": assigns.follow_run.id,
        "phx-value-step_id": assigns.step.id
      ]
    else
      [type: "submit", form: assigns.manual_run_form.id]
    end
  end

  defp save_and_run_classes(assigns) do
    base_class = "relative inline-flex items-center"

    if step_retryable?(assigns) do
      [base_class, "rounded-r-none"]
    else
      [base_class]
    end
  end

  defp create_new_work_order_dropdown(assigns) do
    ~H"""
    <div class="relative -ml-px block">
      <.button
        type="button"
        class="h-full rounded-l-none pr-1 pl-1 focus:ring-inset"
        id="option-menu-button"
        aria-expanded="true"
        aria-haspopup="true"
        disabled={@save_and_run_disabled || @snapshot_version_tag != "latest"}
        phx-click={show_dropdown("create-new-work-order")}
      >
        <span class="sr-only">Open options</span>
        <.icon name="hero-chevron-down" class="w-4 h-4" />
      </.button>
      <div
        role="menu"
        aria-orientation="vertical"
        aria-labelledby="option-menu-button"
        tabindex="-1"
      >
        <button
          phx-click-away={hide_dropdown("create-new-work-order")}
          phx-hook="AltRunViaCtrlShiftEnter"
          id="create-new-work-order"
          type="submit"
          form={@manual_run_form.id}
          class={[
            "hidden absolute right-0 bottom-9 z-10 mb-2 w-max",
            "rounded-md bg-white px-4 py-2 text-sm font-semibold",
            "text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
          ]}
          disabled={@save_and_run_disabled || @snapshot_version_tag != "latest"}
        >
          <.icon name="hero-play-solid" class="w-4 h-4 mr-1" /> Create New Work Order
        </button>
      </div>
    </div>
    """
  end

  defp banner_message(current_user_presence, prior_user_presence) do
    prior_user_name =
      "#{prior_user_presence.user.first_name} #{prior_user_presence.user.last_name}"

    cond do
      current_user_presence.active_sessions > 1 ->
        "You have this workflow open in #{current_user_presence.active_sessions} tabs and can't edit until you close the other#{if current_user_presence.active_sessions > 2, do: "s", else: ""}."

      current_user_presence.user.id != prior_user_presence.user.id ->
        "#{prior_user_name} is currently active and you can't edit this workflow until they close the editor and canvas."

      true ->
        nil
    end
  end

  @spec close_url(map(), atom(), atom()) :: String.t()
  defp close_url(assigns, type, selection) do
    query_params = %{
      "a" => assigns[:selected_run],
      "v" => Ecto.Changeset.get_field(assigns[:changeset], :lock_version)
    }

    query_params =
      case selection do
        :select ->
          Map.merge(query_params, %{"s" => assigns[type] && assigns[type].id})

        :unselect ->
          query_params
      end

    query_string =
      query_params
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> URI.encode_query()

    "#{assigns[:base_url]}?#{query_string}"
  end

  defp display_switcher(snapshot, workflow) do
    snapshot && snapshot.lock_version != workflow.lock_version
  end

  defp step_retryable?(assigns),
    do:
      step_retryable?(
        assigns.step,
        assigns.manual_run_form,
        assigns.selectable_dataclips
      )

  defp step_retryable?(step, form, selectable_dataclips) do
    step_dataclip_id = step && step.input_dataclip_id

    selected_dataclip =
      Enum.find(selectable_dataclips, fn dataclip ->
        dataclip.id == form[:dataclip_id].value
      end)

    selected_dataclip && selected_dataclip.id == step_dataclip_id &&
      is_nil(selected_dataclip.wiped_at)
  end

  defp selected_dataclip_wiped?(form, selectable_dataclips) do
    selected_dataclip =
      Enum.find(selectable_dataclips, fn dataclip ->
        dataclip.id == form[:dataclip_id].value
      end)

    selected_dataclip && !is_nil(selected_dataclip.wiped_at)
  end

  defp processing(%{state: state}) do
    !(state in Lightning.Run.final_states())
  end

  defp processing(_run), do: false

  defp job_deletion_tooltip_message(
         workflow_deleted,
         can_edit_job,
         has_child_edges,
         is_first_job
       ) do
    cond do
      workflow_deleted ->
        "You cannot modify a deleted workflow"

      !can_edit_job ->
        "You are not authorized to delete this step."

      has_child_edges ->
        "You can't delete a step that other downstream steps depend on."

      is_first_job ->
        "You can't delete the first step in a workflow."

      true ->
        nil
    end
  end

  defp job_deleted?(selected_job, workflow) do
    not Enum.any?(workflow.jobs, fn job -> job.id == selected_job.id end)
  end

  defp version_switcher_toggle(assigns) do
    ~H"""
    <div
      id={"version-switcher-toggle-wrapper-#{@id}"}
      phx-click="switch-version"
      phx-value-type="toggle"
      class="flex items-center justify-between mr-1 text-sm z-50 cursor-pointer"
      {if @disabled, do: ["phx-hook": "Tooltip", "data-placement": "top", "aria-label": "Can't switch to the latest version, the job has been deleted from the workflow."], else: []}
    >
      <span class="flex flex-grow flex-col">
        <span class="inline-flex items-center px-2 py-1 font-medium mr-1 text-gray-700">
          <%= @label %>
        </span>
      </span>
      <button
        id={"version-switcher-toggle-#{@id}"}
        phx-click="switch-version"
        phx-value-type="toggle"
        data-version={@version}
        type="button"
        disabled={@disabled}
        class={"#{if @version == "latest", do: "bg-indigo-600", else: "bg-gray-200"} relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent bg-gray-200 transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-indigo-600 focus:ring-offset-2"}
        role="switch"
        aria-checked="false"
      >
        <span class={"pointer-events-none relative inline-block h-5 w-5 translate-x-0 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out #{if @version == "latest", do: "translate-x-5", else: "translate-x-0"}"}>
          <span
            class={"absolute inset-0 flex h-full w-full items-center justify-center transition-opacity #{if @version == "latest", do: "opacity-0 duration-100 ease-out", else: "opacity-100 duration-200 ease-in"}"}
            aria-hidden="true"
          >
            <svg class="h-3 w-3 text-gray-400" fill="none" viewBox="0 0 12 12">
              <path
                d="M4 8l2-2m0 0l2-2M6 6L4 4m2 2l2 2"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
            </svg>
          </span>
          <span
            class={"absolute inset-0 flex h-full w-full items-center justify-center transition-opacity #{if @version == "latest", do: "opacity-100 duration-200 ease-in", else: "opacity-0 duration-100 ease-out"}"}
            aria-hidden="true"
          >
            <svg
              class="h-3 w-3 text-indigo-600"
              fill="currentColor"
              viewBox="0 0 12 12"
            >
              <path d="M3.707 5.293a1 1 0 00-1.414 1.414l1.414-1.414zM5 8l-.707.707a1 1 0 001.414 0L5 8zm4.707-3.293a1 1 0 00-1.414-1.414l1.414 1.414zm-7.414 2l2 2 1.414-1.414-2-2-1.414 1.414zm3.414 2l4-4-1.414-1.414-4 4 1.414 1.414z" />
            </svg>
          </span>
        </span>
      </button>
    </div>
    """
  end

  defp expand_job_editor(assigns) do
    {is_empty, error_message} = editor_is_empty(assigns.form, assigns.job)

    button_base_classes =
      ~w(
        inline-flex items-center rounded-md bg-white px-3.5 py-2.5 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset hover:bg-gray-50)

    button_classes =
      button_base_classes ++
        if is_empty,
          do: ~w(ring-red-300),
          else: ~w(ring-gray-300)

    assigns =
      assign(assigns,
        is_empty: is_empty,
        button_classes: button_classes,
        error_message: error_message
      )

    ~H"""
    <.link
      id={"open-inspector-#{@job.id}"}
      patch={"#{@base_url}?s=#{@job.id}&m=expand" <> (if @snapshot_lock_version, do: "&v=#{@snapshot_lock_version}", else: "") <> (if @selected_run, do: "&a=#{@selected_run}", else: "")}
      class={@button_classes}
    >
      <.icon name="hero-code-bracket" class="w-4 h-4 text-grey-400" />
    </.link>

    <.save_is_blocked_error :if={@is_empty}>
      <%= @error_message %>
    </.save_is_blocked_error>
    """
  end

  defp save_is_blocked_error(assigns) do
    ~H"""
    <span class="flex items-center font-medium text-sm text-red-600 ml-1 mr-4 gap-x-1.5">
      <.icon name="hero-exclamation-circle" class="h-5 w-5" />
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  defp single_inputs_for(form, field, id) do
    %Phoenix.HTML.FormField{field: field_name, form: parent_form} = form[field]

    parent_form.impl.to_form(parent_form.source, parent_form, field_name, [])
    |> Enum.find(&(Ecto.Changeset.get_field(&1.source, :id) == id))
  end

  defp single_inputs_for(%{field: :jobs} = assigns) do
    %{form: form, field: field} = assigns

    %Phoenix.HTML.FormField{field: field_name, form: parent_form} = form[field]

    forms =
      parent_form.impl.to_form(parent_form.source, parent_form, field_name, [])
      |> Enum.filter(&(Ecto.Changeset.get_field(&1.source, :id) == assigns[:id]))

    assigns = assigns |> assign(forms: forms)

    ~H"""
    <%= for f <- @forms do %>
      <%= render_slot(@inner_block, {f}) %>
    <% end %>
    """
  end

  defp single_inputs_for(assigns) do
    %{form: form, field: field} = assigns

    %Phoenix.HTML.FormField{field: field_name, form: parent_form} = form[field]

    forms =
      parent_form.impl.to_form(parent_form.source, parent_form, field_name, [])
      |> Enum.filter(&(Ecto.Changeset.get_field(&1.source, :id) == assigns[:id]))

    assigns = assigns |> assign(forms: forms)

    ~H"""
    <%= for f <- @forms do %>
      <%= render_slot(@inner_block, f) %>
    <% end %>
    """
  end

  def authorize(%{assigns: %{live_action: :new}} = socket) do
    %{project_user: project_user, current_user: current_user, project: project} =
      socket.assigns

    Permissions.can(ProjectUsers, :create_workflow, current_user, project_user)
    |> then(fn
      :ok ->
        socket
        |> assign(
          can_edit_workflow:
            Permissions.can?(
              ProjectUsers,
              :edit_workflow,
              current_user,
              project_user
            ),
          can_run_workflow:
            Permissions.can?(
              ProjectUsers,
              :run_workflow,
              current_user,
              project_user
            ),
          can_write_webhook_auth_method:
            Permissions.can?(
              ProjectUsers,
              :write_webhook_auth_method,
              current_user,
              project_user
            ),
          can_edit_data_retention:
            Permissions.can?(
              ProjectUsers,
              :edit_data_retention,
              current_user,
              project_user
            )
        )

      {:error, _} ->
        socket
        |> put_flash(:error, "You are not authorized to perform this action.")
        |> push_navigate(to: ~p"/projects/#{project.id}/w")
    end)
  end

  def authorize(%{assigns: %{live_action: :edit}} = socket) do
    %{project_user: project_user, current_user: current_user} = socket.assigns

    socket
    |> assign(
      can_write_webhook_auth_method:
        Permissions.can?(
          ProjectUsers,
          :write_webhook_auth_method,
          current_user,
          project_user
        ),
      can_edit_workflow:
        Permissions.can?(
          ProjectUsers,
          :edit_workflow,
          current_user,
          project_user
        ),
      can_run_workflow:
        Permissions.can?(ProjectUsers, :run_workflow, current_user, project_user),
      can_edit_data_retention:
        Permissions.can?(
          ProjectUsers,
          :edit_data_retention,
          current_user,
          project_user
        )
    )
  end

  @impl true
  def mount(_params, _session, %{assigns: assigns} = socket) do
    view_only_users_ids =
      assigns.project |> view_only_users() |> Enum.map(fn pu -> pu.user.id end)

    {:ok,
     socket
     |> authorize()
     |> assign(
       view_only_users_ids: view_only_users_ids,
       active_menu_item: :overview,
       expanded_job: nil,
       ai_assistant_enabled: AiAssistant.enabled?(),
       project_has_chat_sessions: nil,
       chat_session_id: nil,
       follow_run: nil,
       step: nil,
       manual_run_form: nil,
       page_title: "",
       selected_edge: nil,
       selected_job: nil,
       selected_run: nil,
       selected_trigger: nil,
       selection_mode: nil,
       query_params: %{
         "s" => nil,
         "m" => nil,
         "a" => nil,
         "v" => nil,
         "chat" => nil
       },
       workflow: nil,
       snapshot: nil,
       changeset: nil,
       snapshot_version_tag: "latest",
       workflow_name: "",
       workflow_params: %{},
       selected_credential_type: nil,
       oauth_clients: OauthClients.list_clients(assigns.project),
       show_missing_dataclip_selector: false,
       admin_contacts: Projects.list_project_admin_emails(assigns.project.id)
     )
     |> assign(initial_presence_summary(socket.assigns.current_user))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     apply_action(socket, socket.assigns.live_action, params)
     |> track_user_presence()
     |> apply_query_params(params)
     |> maybe_show_manual_run()
     |> tap(fn socket ->
       if connected?(socket) do
         Workflows.Events.subscribe(socket.assigns.project.id)

         if changed?(socket, :selected_job) do
           Helpers.broadcast_updated_params(socket, %{
             job_id:
               case socket.assigns.selected_job do
                 nil -> nil
                 job -> job.id
               end
           })
         end
       end
     end)}
  end

  def apply_action(socket, :new, params) do
    if socket.assigns.workflow do
      socket
    else
      socket
      |> assign_workflow(%Workflow{
        project_id: socket.assigns.project.id,
        name: params["name"],
        id: Ecto.UUID.generate()
      })
    end
    |> assign(page_title: params["name"])
  end

  def apply_action(socket, :edit, %{"id" => workflow_id} = params) do
    case socket.assigns.workflow do
      %{id: ^workflow_id} ->
        socket

      _ ->
        # TODO we shouldn't be calling Repo from here
        workflow = get_workflow_by_id(workflow_id)

        if workflow do
          run_id = Map.get(params, "a")
          version = Map.get(params, "v") || workflow.lock_version

          snapshot = snapshot_by_version(workflow.id, version)

          socket
          |> assign(selected_run: run_id)
          |> assign_workflow(workflow, snapshot)
          |> assign(page_title: workflow.name)
        else
          socket
          |> put_flash(:error, "Workflow not found")
          |> push_navigate(to: ~p"/projects/#{socket.assigns.project}/w")
        end
    end
    |> assign(
      project_has_chat_sessions:
        AiAssistant.project_has_any_session?(socket.assigns.project.id)
    )
  end

  defp track_user_presence(socket) do
    if connected?(socket) && socket.assigns.snapshot_version_tag == "latest" do
      Presence.track_user_presence(
        socket.assigns.current_user,
        "workflow-#{socket.assigns.workflow.id}:presence",
        self()
      )
    end

    socket
  end

  defp view_only_users(project) do
    Lightning.Repo.preload(project, project_users: [:user])
    |> Map.get(:project_users)
    |> Enum.filter(fn pu -> pu.role == :viewer end)
  end

  defp snapshot_by_version(workflow_id, version),
    do: Snapshot.get_by_version(workflow_id, version)

  defp remove_edges_from_params(initial_params, edges_to_delete, id) do
    Map.update!(initial_params, "edges", fn edges ->
      edges
      |> Enum.reject(fn edge ->
        edge["id"] in Enum.map(edges_to_delete, & &1.id)
      end)
    end)
    |> Map.update!("jobs", &Enum.reject(&1, fn job -> job["id"] == id end))
  end

  defp toggle_latest_version(socket) do
    %{
      changeset: prev_changeset,
      project: project,
      workflow: workflow,
      selected_job: selected_job
    } =
      socket.assigns

    if job_deleted?(selected_job, workflow) do
      put_flash(
        socket,
        :info,
        "Can't switch to the latest version, the job has been deleted from the workflow."
      )
    else
      {next_changeset, version} = switch_changeset(socket)

      prev_params = WorkflowParams.to_map(prev_changeset)
      next_params = WorkflowParams.to_map(next_changeset)

      patches = WorkflowParams.to_patches(prev_params, next_params)

      lock_version = Ecto.Changeset.get_field(next_changeset, :lock_version)

      query_params =
        socket.assigns.query_params
        |> Map.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.put("v", lock_version)

      url = ~p"/projects/#{project.id}/w/#{workflow.id}?#{query_params}"

      if version != "latest" do
        Presence.untrack(
          self(),
          "workflow-#{socket.assigns.workflow.id}:presence",
          socket.assigns.current_user.id
        )
      end

      socket
      |> assign(changeset: next_changeset)
      |> assign(workflow_params: next_params)
      |> assign(snapshot_version_tag: version)
      |> push_event("patches-applied", %{patches: patches})
      |> maybe_disable_canvas()
      |> push_patch(to: url)
    end
  end

  defp commit_latest_version(socket) do
    %{changeset: prev_changeset, project: project, workflow: workflow} =
      socket.assigns

    snapshot = snapshot_by_version(workflow.id, workflow.lock_version)

    next_changeset = Ecto.Changeset.change(workflow)

    prev_params = WorkflowParams.to_map(prev_changeset)
    next_params = WorkflowParams.to_map(next_changeset)

    patches = WorkflowParams.to_patches(prev_params, next_params)

    lock_version =
      Ecto.Changeset.get_field(next_changeset, :lock_version)

    query_params =
      socket.assigns.query_params
      |> Map.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.put("v", lock_version)

    url = ~p"/projects/#{project.id}/w/#{workflow.id}?#{query_params}"

    socket
    |> assign_workflow(workflow, snapshot)
    |> push_event("patches-applied", %{patches: patches})
    |> push_patch(to: url)
  end

  @impl true
  def handle_event("get-initial-state", _params, socket) do
    {:noreply,
     socket
     |> push_event("current-workflow-params", %{
       workflow_params: socket.assigns.workflow_params
     })}
  end

  def handle_event("get-current-state", _params, socket) do
    {:reply, %{workflow_params: socket.assigns.workflow_params}, socket}
  end

  def handle_event("switch-version", %{"type" => type}, socket) do
    updated_socket =
      case type do
        "commit" -> commit_latest_version(socket)
        "toggle" -> toggle_latest_version(socket)
      end

    {:noreply, updated_socket}
  end

  def handle_event("delete_node", %{"id" => id}, socket) do
    %{
      changeset: changeset,
      workflow_params: initial_params,
      can_edit_workflow: can_edit_workflow,
      has_child_edges: has_child_edges,
      is_first_job: is_first_job,
      snapshot_version_tag: tag,
      has_presence_edit_priority: has_presence_edit_priority
    } = socket.assigns

    with true <- can_edit_workflow || :not_authorized,
         true <- !has_child_edges || :has_child_edges,
         true <- !is_first_job || :is_first_job,
         true <- tag == "latest" || :view_only,
         true <-
           has_presence_edit_priority ||
             :presence_low_priority do
      edges_to_delete =
        Ecto.Changeset.get_assoc(changeset, :edges, :struct)
        |> Enum.filter(&(&1.target_job_id == id))

      next_params = remove_edges_from_params(initial_params, edges_to_delete, id)

      {:noreply,
       socket
       |> apply_params(next_params, :workflow)
       |> push_patches_applied(initial_params)}
    else
      :not_authorized ->
        {:noreply,
         socket
         |> put_flash(:error, "You are not authorized to perform this action.")}

      :has_child_edges ->
        {:noreply,
         socket
         |> put_flash(:error, "Delete all descendant steps first.")}

      :is_first_job ->
        {:noreply,
         socket
         |> put_flash(:error, "You can't delete the first step in a workflow.")}

      :view_only ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Cannot delete a step in snapshot mode, switch to latest"
         )}

      :presence_low_priority ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Cannot delete a step in view-only mode"
         )}
    end
  end

  def handle_event("delete_edge", %{"id" => id}, socket) do
    %{
      changeset: changeset,
      workflow_params: initial_params,
      can_edit_workflow: can_edit_workflow,
      selected_edge: selected_edge,
      snapshot_version_tag: tag,
      has_presence_edit_priority: has_presence_edit_priority
    } = socket.assigns

    with true <- can_edit_workflow || :not_authorized,
         true <-
           (selected_edge && is_nil(selected_edge.source_trigger_id)) ||
             :is_initial_edge,
         true <- tag == "latest" || :view_only,
         true <-
           has_presence_edit_priority ||
             :presence_low_priority do
      edges_to_delete =
        Ecto.Changeset.get_assoc(changeset, :edges, :struct)
        |> Enum.filter(&(&1.id == id))

      next_params = remove_edges_from_params(initial_params, edges_to_delete, id)

      {:noreply,
       socket
       |> apply_params(next_params, :workflow)
       |> push_patches_applied(initial_params)}
    else
      :is_initial_edge ->
        {:noreply,
         socket
         |> put_flash(:error, "You cannot remove the first edge in a workflow.")}

      :not_authorized ->
        {:noreply,
         socket
         |> put_flash(:error, "You are not authorized to delete edges.")}

      :view_only ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Cannot delete an edge in snapshot mode, switch to latest"
         )}

      :presence_low_priority ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Cannot delete an edge in view-only mode"
         )}
    end
  end

  def handle_event("validate", %{"workflow" => params}, socket) do
    {:noreply, handle_new_params(socket, params, :workflow)}
  end

  def handle_event("validate", %{"snapshot" => params}, socket) do
    {:noreply, handle_new_params(socket, params, :snapshot)}
  end

  # TODO: remove this and the matching hidden input when issue resolved in LiveView.
  # The hidden input is a workaround for a bug in LiveView where the form is
  # considered for recovery because it has a submit button, but skips the
  # recovery because it has no inputs.
  # This causes the LiveView to not be set as joined, and further diffs to
  # not be applied.
  def handle_event("validate", %{"_ignore_me" => _}, socket) do
    {:noreply, socket}
  end

  def handle_event("save", params, socket) do
    # <<<<<<< HEAD
    #     %{
    #       current_user: current_user,
    #       project: project,
    #       workflow_params: initial_params,
    #       can_edit_workflow: can_edit_workflow,
    #       snapshot_version_tag: tag,
    #       has_presence_edit_priority: has_presence_edit_priority
    #     } =
    #       socket.assigns
    # =======
    %{
      project: project,
      workflow_params: initial_params,
      current_user: current_user
    } = socket.assigns

    # >>>>>>> origin/main

    with :ok <- check_user_can_save_workflow(socket) do
      next_params =
        case params do
          %{"workflow" => params} ->
            WorkflowParams.apply_form_params(
              initial_params,
              params
            )

          %{} ->
            initial_params
        end

      %{assigns: %{changeset: changeset}} =
        socket = socket |> apply_params(next_params, :workflow)

      case Helpers.save_workflow(changeset, current_user) do
        {:ok, workflow} ->
          snapshot = snapshot_by_version(workflow.id, workflow.lock_version)

          query_params =
            socket.assigns.query_params
            |> Map.put("v", workflow.lock_version)
            |> Map.reject(fn {_key, value} -> is_nil(value) end)

          {:noreply,
           socket
           |> assign(page_title: workflow.name)
           |> assign_workflow(workflow, snapshot)
           |> put_flash(:info, "Workflow saved")
           |> push_patches_applied(initial_params)
           |> maybe_push_workflow_created(workflow)
           |> push_patch(
             to: ~p"/projects/#{project.id}/w/#{workflow.id}?#{query_params}",
             replace: true
           )}

        {:error, %{text: message}} ->
          {:noreply, put_flash(socket, :error, message)}

        {:error, :workflow_deleted} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Oops! You cannot modify a deleted workflow"
           )}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           socket
           |> assign_changeset(changeset)
           |> mark_validated()
           |> put_flash(:error, "Workflow could not be saved")
           |> push_patches_applied(initial_params)}
      end
    end
  end

  def handle_event("push-change", %{"patches" => patches}, socket) do
    # Apply the incoming patches to the current workflow params producing a new
    # set of params.
    {:ok, params} =
      WorkflowParams.apply_patches(socket.assigns.workflow_params, patches)

    version_type =
      if socket.assigns.snapshot_version_tag == "latest" do
        :workflow
      else
        :snapshot
      end

    socket = socket |> apply_params(params, version_type)

    # Calculate the difference between the new params and changes introduced by
    # the changeset/validation.
    patches = WorkflowParams.to_patches(params, socket.assigns.workflow_params)

    {:reply, %{patches: patches}, socket |> apply_query_params()}
  end

  def handle_event("copied_to_clipboard", _, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Copied webhook URL to clipboard")}
  end

  def handle_event("toggle_missing_dataclip_selector", _, socket) do
    {:noreply,
     update(socket, :show_missing_dataclip_selector, fn val -> !val end)}
  end

  def handle_event("manual_run_change", %{"manual" => params}, socket) do
    changeset =
      WorkOrders.Manual.new(
        params,
        project: socket.assigns.project,
        workflow: socket.assigns.workflow,
        job: socket.assigns.selected_job,
        created_by: socket.assigns.current_user
      )
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign_manual_run_form(changeset)}
  end

  # Handle empty manual run form submission, this happens when the dataclip
  # dropdown is disabled and the socket reconnects.
  def handle_event("manual_run_change", _params, socket) do
    {:noreply, socket}
  end

  # The retry_from_run event is for creating a new run for an existing work
  # order, just like clicking "rerun from here" on the history page.
  def handle_event(
        "rerun",
        %{"run_id" => run_id, "step_id" => step_id},
        socket
      ) do
    case rerun(socket, run_id, step_id) do
      {:ok, socket} ->
        {:noreply, socket}

      {:error, _reason, %{text: error_text}} ->
        {:noreply, put_flash(socket, :error, error_text)}

      {:error, %{text: message}} ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, :workflow_deleted} ->
        {:noreply,
         put_flash(socket, :error, "Cannot rerun a deleted a workflow")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign_changeset(socket.assigns.changeset)
         |> mark_validated()
         |> put_flash(:error, "Workflow could not be saved")}

      :not_authorized ->
        {:noreply,
         socket
         |> put_flash(:error, "You are not authorized to perform this action.")}

      :view_only ->
        {:noreply,
         socket
         |> put_flash(:error, "Cannot rerun in snapshot mode, switch to latest.")}
    end
  end

  # The manual_run_submit event is for create a new work order from a dataclip and
  # a job.
  def handle_event("manual_run_submit", params, socket) do
    %{
      project: project,
      selected_job: selected_job,
      current_user: current_user,
      workflow_params: workflow_params,
      has_presence_edit_priority: has_presence_edit_priority,
      workflow: workflow,
      manual_run_form: form
    } = socket.assigns

    manual_params = Map.get(params, "manual", %{})

    params =
      case form do
        nil -> manual_params
        %{params: form_params} -> Map.merge(form_params, manual_params)
      end

    socket = socket |> apply_params(workflow_params, :workflow)

    workflow_or_changeset =
      if has_presence_edit_priority do
        socket.assigns.changeset
      else
        get_workflow_by_id(workflow.id)
      end

    with :ok <- check_user_can_manual_run_workflow(socket) do
      case Helpers.run_workflow(
             workflow_or_changeset,
             params,
             project: project,
             selected_job: selected_job,
             created_by: current_user
           ) do
        {:ok, %{workorder: workorder, workflow: workflow}} ->
          %{runs: [run]} = workorder

          Runs.subscribe(run)

          snapshot = snapshot_by_version(workflow.id, workflow.lock_version)

          {:noreply,
           socket
           |> assign_workflow(workflow, snapshot)
           |> follow_run(run)
           |> push_event("push-hash", %{"hash" => "log"})}

        {:error, %Ecto.Changeset{data: %WorkOrders.Manual{}} = changeset} ->
          {:noreply,
           socket
           |> assign_manual_run_form(changeset)}

        {:error, %Ecto.Changeset{data: %Workflow{}} = changeset} ->
          {
            :noreply,
            socket
            |> assign_changeset(changeset)
            |> mark_validated()
            |> put_flash(:error, "Workflow could not be saved")
          }

        {:error, %{text: message}} ->
          {:noreply, put_flash(socket, :error, message)}

        {:error, :workflow_deleted} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Oops! You cannot modify a deleted workflow"
           )}
      end
    end
  end

  def handle_event(_unhandled_event, _params, socket) do
    # TODO: add a warning and/or log for unhandled events
    {:noreply, socket}
  end

  @impl true
  def handle_info(
        %WorkflowUpdated{workflow: updated_workflow},
        socket
      ) do
    %{
      workflow: current_workflow,
      snapshot_version_tag: version_tag,
      has_presence_edit_priority: has_edit_priority?,
      snapshot: snapshot
    } = socket.assigns

    is_same_workflow? = current_workflow.id == updated_workflow.id
    is_latest_version? = version_tag == "latest"
    should_update? = is_same_workflow? and not has_edit_priority?

    if should_update? do
      updated_socket =
        if is_latest_version? do
          put_flash(
            socket,
            :info,
            "This workflow has been updated. You're no longer on the latest version."
          )
        else
          socket
        end

      {:noreply, assign_workflow(updated_socket, updated_workflow, snapshot)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({"form_changed", %{"workflow" => params}}, socket) do
    {:noreply, handle_new_params(socket, params, :workflow)}
  end

  def handle_info({"form_changed", %{"snapshot" => params}}, socket) do
    {:noreply, handle_new_params(socket, params, :snapshot)}
  end

  def handle_info({:forward, mod, opts}, socket) do
    send_update(mod, opts)
    {:noreply, socket}
  end

  def handle_info(%DataclipUpdated{dataclip: dataclip}, socket) do
    dataclip = Invocation.get_dataclip!(dataclip.id)

    {:noreply,
     assign_dataclips(socket, socket.assigns.selectable_dataclips, dataclip)}
  end

  def handle_info(
        %StepCompleted{step: step},
        socket
      )
      when step.job_id === socket.assigns.selected_job.id do
    {:noreply, assign(socket, step: step)}
  end

  def handle_info(
        %RunUpdated{run: run},
        %{assigns: %{follow_run: %{id: follow_run_id}}} = socket
      )
      when run.id === follow_run_id do
    {:noreply,
     socket
     |> assign(follow_run: run)}
  end

  def handle_info(%{event: "presence_diff", payload: _diff}, socket) do
    summary =
      "workflow-#{socket.assigns.workflow.id}:presence"
      |> Presence.list_presences()
      |> Presence.build_presences_summary(socket.assigns)

    {:noreply,
     socket
     |> assign(summary)
     |> maybe_switch_workflow_version()
     |> maybe_disable_canvas()}
  end

  def handle_info(%{}, socket) do
    {:noreply, socket}
  end

  defp check_user_can_manual_run_workflow(socket) do
    case socket.assigns do
      %{
        can_edit_workflow: true,
        can_run_workflow: true,
        snapshot_version_tag: "latest"
      } ->
        :ok

      %{can_edit_workflow: false} ->
        {:noreply,
         socket
         |> put_flash(:error, "You are not authorized to perform this action.")}

      %{can_run_workflow: false} ->
        {:noreply,
         socket
         |> put_flash(:error, "You are not authorized to perform this action.")}

      _snapshot_not_latest ->
        {:noreply,
         socket
         |> put_flash(:error, "Cannot run in snapshot mode, switch to latest.")}
    end
  end

  defp check_user_can_save_workflow(socket) do
    case socket.assigns do
      %{
        can_edit_workflow: true,
        has_presence_edit_priority: true,
        snapshot_version_tag: "latest"
      } ->
        :ok

      %{can_edit_workflow: false} ->
        {:noreply,
         socket
         |> put_flash(:error, "You are not authorized to perform this action.")}

      %{has_presence_edit_priority: false} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Cannot save in view-only mode"
         )}

      _snapshot_not_latest ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Cannot save in snapshot mode, switch to the latest version."
         )}
    end
  end

  defp maybe_disable_canvas(socket) do
    %{
      has_presence_edit_priority: has_edit_priority,
      snapshot_version_tag: version,
      can_edit_workflow: can_edit_workflow,
      workflow: workflow
    } = socket.assigns

    disabled =
      !(is_nil(workflow.deleted_at) && has_edit_priority && version == "latest" &&
          can_edit_workflow)

    push_event(socket, "set-disabled", %{disabled: disabled})
  end

  defp maybe_switch_workflow_version(socket) do
    %{
      workflow: workflow,
      prior_user_presence: prior_presence,
      current_user: current_user,
      selected_run: selected_run
    } = socket.assigns

    if prior_presence.user.id == current_user.id &&
         Workflows.has_newer_version?(workflow) do
      reloaded_workflow = get_workflow_by_id(workflow.id)

      socket = assign(socket, workflow: reloaded_workflow)

      if selected_run do
        toggle_latest_version(socket)
      else
        commit_latest_version(socket)
      end
    else
      socket
    end
  end

  defp get_workflow_by_id(workflow_id) do
    Workflows.get_workflow(workflow_id)
    |> Lightning.Repo.preload([
      :edges,
      triggers: Trigger.with_auth_methods_query(),
      jobs:
        {Workflows.jobs_ordered_subquery(),
         [:credential, steps: Invocation.Query.any_step()]}
    ])
  end

  defp initial_presence_summary(current_user) do
    init_user_presence = %Presence{
      user: current_user,
      active_sessions: 1
    }

    %{
      presences: [],
      prior_user_presence: init_user_presence,
      current_user_presence: init_user_presence,
      has_presence_edit_priority: true
    }
  end

  defp maybe_show_manual_run(socket) do
    case socket.assigns do
      %{selected_job: nil} ->
        socket
        |> assign(
          manual_run_form: nil,
          selectable_dataclips: []
        )

      %{selected_job: job, selection_mode: "expand"} = assigns
      when not is_nil(job) ->
        dataclip =
          assigns[:follow_run] &&
            get_selected_dataclip(assigns[:follow_run], job.id)

        changeset =
          WorkOrders.Manual.new(
            %{dataclip_id: dataclip && dataclip.id},
            project: socket.assigns.project,
            workflow: socket.assigns.workflow,
            job: socket.assigns.selected_job,
            user: socket.assigns.current_user
          )

        selectable_dataclips =
          Invocation.list_dataclips_for_job(%Job{id: job.id})

        step =
          assigns[:follow_run] &&
            Invocation.get_first_step_for_run_and_job(
              assigns[:follow_run].id,
              job.id
            )

        socket
        |> assign_manual_run_form(changeset)
        |> assign(step: step)
        |> assign_dataclips(selectable_dataclips, dataclip)

      _ ->
        socket
    end
  end

  defp assign_dataclips(socket, selectable_dataclips, step_dataclip) do
    socket
    |> assign(
      selectable_dataclips:
        maybe_add_selected_dataclip(selectable_dataclips, step_dataclip)
    )
    |> assign(show_missing_dataclip_selector: is_map(step_dataclip))
  end

  defp get_selected_dataclip(run, job_id) do
    dataclip = Invocation.get_first_dataclip_for_run_and_job(run.id, job_id)

    if is_nil(dataclip) and
         (run.starting_job_id == job_id ||
            Invocation.get_step_count_for_run(run.id) == 0) do
      Invocation.get_dataclip_for_run(run.id)
    else
      dataclip
    end
  end

  defp maybe_add_selected_dataclip(selectable_dataclips, nil) do
    selectable_dataclips
  end

  defp maybe_add_selected_dataclip(selectable_dataclips, dataclip) do
    existing_index =
      Enum.find_index(selectable_dataclips, fn dc -> dc.id == dataclip.id end)

    if existing_index do
      List.replace_at(selectable_dataclips, existing_index, dataclip)
    else
      [dataclip | selectable_dataclips]
    end
  end

  defp assign_manual_run_form(socket, changeset) do
    assign(socket, manual_run_form: to_form(changeset, id: "manual_run_form"))
  end

  defp save_and_run_disabled?(attrs) do
    case attrs do
      %{manual_run_form: nil} ->
        true

      %{workflow: %{deleted_at: deleted_at}} when is_struct(deleted_at) ->
        true

      %{
        manual_run_form: manual_run_form,
        changeset: changeset,
        can_edit_workflow: can_edit_workflow,
        can_run_workflow: can_run_workflow
      } ->
        form_valid =
          if manual_run_form.source.errors == [
               created_by: {"can't be blank", [validation: :required]}
             ] and Map.get(manual_run_form.params, "dataclip_id") do
            true
          else
            !Enum.any?(manual_run_form.source.errors)
          end

        !form_valid or
          !changeset.valid? or
          !(can_edit_workflow or can_run_workflow)
    end
  end

  defp editor_is_empty(form, job) do
    %Phoenix.HTML.FormField{field: field_name, form: parent_form} = form[:jobs]

    found_job =
      parent_form.impl.to_form(parent_form.source, parent_form, field_name, [])
      |> Enum.find(fn f -> Ecto.Changeset.get_field(f.source, :id) == job.id end)

    if found_job do
      errors =
        found_job
        |> Map.get(:source)
        |> Map.get(:errors)

      error_message = LightningWeb.CoreComponents.translate_errors(errors, :body)

      is_empty? = Keyword.has_key?(errors, :body)

      {is_empty?, error_message}
    else
      {false, nil}
    end
  end

  defp has_child_edges?(workflow_changeset, job_id) do
    workflow_changeset
    |> get_filtered_edges(&(&1.source_job_id == job_id))
    |> Enum.any?()
  end

  defp first_job?(workflow_changeset, job_id) do
    workflow_changeset
    |> get_filtered_edges(&(&1.source_trigger_id && &1.target_job_id == job_id))
    |> Enum.any?()
  end

  defp get_filtered_edges(workflow_changeset, filter_func) do
    workflow_changeset
    |> Ecto.Changeset.get_assoc(:edges, :struct)
    |> Enum.filter(filter_func)
  end

  defp handle_new_params(socket, params, type) do
    %{workflow_params: initial_params, can_edit_workflow: can_edit_workflow} =
      socket.assigns

    if can_edit_workflow do
      next_params =
        WorkflowParams.apply_form_params(socket.assigns.workflow_params, params)

      socket
      |> apply_params(next_params, type)
      |> mark_validated()
      |> push_patches_applied(initial_params)
    else
      socket
      |> put_flash(:error, "You are not authorized to perform this action.")
    end
  end

  defp send_form_changed(params) do
    send(self(), {"form_changed", params})
  end

  defp assign_workflow(socket, workflow) do
    socket
    |> assign(workflow: workflow)
    |> apply_params(socket.assigns.workflow_params, :workflow)
  end

  defp assign_workflow(socket, workflow, snapshot) do
    {changeset, version} =
      if snapshot.lock_version == workflow.lock_version do
        {Ecto.Changeset.change(workflow), "latest"}
      else
        {Ecto.Changeset.change(snapshot), String.slice(snapshot.id, 0..6)}
      end

    socket
    |> assign(workflow: workflow)
    |> assign(snapshot: snapshot)
    |> assign(snapshot_version_tag: version)
    |> assign_changeset(changeset)
    |> maybe_disable_canvas()
  end

  defp apply_params(socket, params, type) do
    changeset =
      case type do
        :snapshot ->
          Ecto.Changeset.change(socket.assigns.snapshot)

        :workflow ->
          socket.assigns.workflow
          |> Workflow.changeset(
            params
            |> set_default_adaptors()
            |> Map.put("project_id", socket.assigns.project.id)
          )
      end

    assign_changeset(socket, changeset)
  end

  defp apply_query_params(socket, params) do
    socket
    |> assign(
      query_params:
        params
        |> Map.take(["s", "m", "a", "v", "chat"])
        |> Enum.into(%{
          "s" => nil,
          "m" => nil,
          "a" => nil,
          "v" => nil,
          "chat" => nil
        })
    )
    |> apply_query_params()
  end

  defp apply_query_params(socket) do
    socket.assigns.query_params
    |> case do
      %{"m" => "settings", "s" => nil, "a" => nil} ->
        socket |> unselect_all() |> set_mode("settings")

      # Nothing is selected
      %{"s" => nil} ->
        socket |> unselect_all() |> set_mode(nil)

      # Try to select the given item, possibly with a mode (such as `expand`)
      %{"s" => selected_id, "m" => mode} ->
        case find_item(socket.assigns.changeset, selected_id) do
          [type, selected] ->
            socket
            |> set_selected_node(type, selected)
            |> set_mode(if mode in ["expand"], do: mode, else: nil)

          nil ->
            socket |> unselect_all()
        end
    end
    |> assign_follow_run(socket.assigns.query_params)
    |> assign_chat_session_id(socket.assigns.query_params)
  end

  defp assign_chat_session_id(socket, %{"chat" => session_id})
       when is_binary(session_id) do
    socket
    |> assign(chat_session_id: session_id)
  end

  defp assign_chat_session_id(socket, _params) do
    socket
    |> assign(chat_session_id: nil)
  end

  defp switch_changeset(socket) do
    %{changeset: changeset, workflow: workflow, snapshot: snapshot} =
      socket.assigns

    case changeset do
      %Ecto.Changeset{data: %Snapshot{}} ->
        {Ecto.Changeset.change(workflow), "latest"}

      %Ecto.Changeset{data: %Workflow{}} ->
        {Ecto.Changeset.change(snapshot), String.slice(snapshot.id, 0..6)}
    end
  end

  defp assign_changeset(socket, changeset) do
    workflow_params = WorkflowParams.to_map(changeset)

    socket
    |> assign(
      changeset: changeset,
      workflow_params: workflow_params
    )
  end

  defp push_patches_applied(socket, initial_params) do
    next_params = socket.assigns.workflow_params

    patches =
      WorkflowParams.to_patches(initial_params, next_params)

    socket
    |> push_event("patches-applied", %{patches: patches})
  end

  defp maybe_push_workflow_created(socket, workflow) do
    if socket.assigns.live_action == :new do
      push_event(socket, "workflow_created", %{id: workflow.id})
    else
      socket
    end
  end

  # In situations where a new job is added, specifically by the WorkflowDiagram
  # component, the job will not have an adaptor set. This function will set the
  # adaptor to the current latest version of the adaptor, instead of the
  # `@latest` version.
  defp set_default_adaptors(params) do
    case params do
      %{"jobs" => job_params} ->
        params
        |> Map.put("jobs", job_params |> Enum.map(&maybe_add_default_adaptor/1))

      _ ->
        params
    end
  end

  defp maybe_add_default_adaptor(job_param) do
    if Map.keys(job_param) == ["id"] do
      job_param
      |> Map.put(
        "adaptor",
        Lightning.AdaptorRegistry.resolve_adaptor(%Job{}.adaptor)
      )
    else
      job_param
    end
  end

  defp unselect_all(socket) do
    socket
    |> assign(
      selected_edge: nil,
      selected_job: nil,
      selected_trigger: nil,
      selection_mode: nil,
      chat_session_id: nil
    )
  end

  defp set_mode(socket, mode) do
    if mode in [nil, "expand", "settings"] do
      socket
      |> assign(selection_mode: mode)
    else
      socket
    end
  end

  defp set_selected_node(socket, type, value) do
    case type do
      :jobs ->
        socket
        |> assign(
          has_child_edges: has_child_edges?(socket.assigns.changeset, value.id),
          is_first_job: first_job?(socket.assigns.changeset, value.id),
          selected_job: value,
          selected_trigger: nil,
          selected_edge: nil
        )

      :triggers ->
        socket
        |> assign(
          selected_job: nil,
          selected_trigger: value,
          selected_edge: nil,
          chat_session_id: nil
        )

      :edges ->
        socket
        |> assign(
          selected_job: nil,
          selected_trigger: nil,
          selected_edge: value,
          chat_session_id: nil
        )
    end
  end

  defp follow_run(socket, run) do
    %{query_params: query_params, project: project, workflow: workflow} =
      socket.assigns

    version =
      Ecto.Changeset.get_field(socket.assigns.changeset, :lock_version)

    params =
      query_params
      |> Map.put("a", run.id)
      |> Map.put("v", version)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    socket
    |> push_patch(to: ~p"/projects/#{project}/w/#{workflow}?#{params}")
  end

  defp assign_follow_run(socket, %{"a" => run_id}) when is_binary(run_id) do
    assign_follow_run(socket, run_id)
  end

  defp assign_follow_run(socket, query_params) when is_map(query_params) do
    assign(socket, follow_run: nil)
  end

  defp assign_follow_run(%{assigns: %{selected_job: nil}} = socket, _run_id) do
    assign(socket, follow_run: nil)
  end

  defp assign_follow_run(%{assigns: %{selected_job: job}} = socket, run_id)
       when is_binary(run_id) do
    run = Runs.get(run_id)
    step = Invocation.get_first_step_for_run_and_job(run_id, job.id)

    Runs.subscribe(run)

    assign(socket, follow_run: run, step: step)
  end

  defp find_item(%Ecto.Changeset{} = changeset, id) do
    find_item_helper(changeset, id, fn data, field ->
      Ecto.Changeset.get_assoc(data, field, :struct)
    end)
  end

  defp find_item_helper(data, id, accessor) do
    [:jobs, :triggers, :edges]
    |> Enum.reduce_while(nil, fn field, _ ->
      accessor.(data, field)
      |> Enum.find(&(&1.id == id))
      |> case do
        nil ->
          {:cont, nil}

        %Job{} = job ->
          {:halt,
           [
             field,
             job
             |> Lightning.Repo.preload([
               :credential,
               steps: Invocation.Query.any_step()
             ])
           ]}

        %Trigger{} = trigger ->
          {:halt,
           [field, Lightning.Repo.preload(trigger, :webhook_auth_methods)]}

        item ->
          {:halt, [field, item]}
      end
    end)
  end

  defp mark_validated(socket) do
    socket
    |> assign(changeset: socket.assigns.changeset |> Map.put(:action, :validate))
  end

  defp with_changes_indicator(assigns) do
    ~H"""
    <div class="relative">
      <div
        :if={@changeset.changes |> Enum.any?()}
        class="absolute -m-1 rounded-full bg-danger-500 w-3 h-3 top-0 right-0"
        data-is-dirty="true"
      >
      </div>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :can_edit_workflow, :boolean, required: true
  attr :changeset, Ecto.Changeset, required: true
  attr :snapshot_version_tag, :string, required: true
  attr :has_presence_priority, :boolean, required: true

  defp save_workflow_button(assigns) do
    {disabled, tooltip} =
      case assigns do
        %{
          changeset: %{valid?: true, data: %{deleted_at: nil}},
          can_edit_workflow: true,
          snapshot_version_tag: "latest",
          has_presence_priority: true
        } ->
          {false, nil}

        %{changeset: %{data: %{deleted_at: deleted_at}}}
        when is_struct(deleted_at) ->
          {true, "Workflow has been deleted"}

        %{can_edit_workflow: false} ->
          {true, "You do not have permission to edit this workflow"}

        %{changeset: %{valid?: false}} ->
          {true, "You have some unresolved errors in your workflow"}

        %{snapshot_version_tag: tag} when tag != "latest" ->
          {true, "You cannot edit an old snapshot of a workflow"}

        _other ->
          {true, nil}
      end

    assigns =
      assigns
      |> assign(
        disabled: disabled,
        tooltip: tooltip
      )

    ~H"""
    <.button
      id={@id}
      phx-disable-with="Saving..."
      disabled={@disabled}
      type="submit"
      form="workflow-form"
      phx-disconnected={JS.set_attribute({"disabled", ""})}
      tooltip={@tooltip}
      phx-connected={
        !@disabled && !@has_presence_priority && JS.remove_attribute("disabled")
      }
    >
      Save
    </.button>
    """
  end

  defp rerun(socket, run_id, step_id) do
    %{
      can_run_workflow: can_run_workflow?,
      current_user: current_user,
      changeset: changeset,
      project: %{id: project_id},
      snapshot_version_tag: tag,
      has_presence_edit_priority: has_edit_priority?,
      workflow: %{id: workflow_id}
    } = socket.assigns

    save_or_get_workflow =
      if has_edit_priority? do
        Helpers.save_workflow(%{changeset | action: :update}, current_user)
      else
        {:ok, get_workflow_by_id(workflow_id)}
      end

    with true <- can_run_workflow? || :not_authorized,
         true <- tag == "latest" || :view_only,
         :ok <-
           UsageLimiter.limit_action(%Action{type: :new_run}, %Context{
             project_id: project_id
           }),
         {:ok, workflow} <- save_or_get_workflow,
         {:ok, run} <-
           WorkOrders.retry(run_id, step_id, created_by: current_user) do
      Runs.subscribe(run)

      snapshot = Snapshot.get_by_version(workflow.id, workflow.lock_version)

      {:ok,
       socket
       |> assign_workflow(workflow, snapshot)
       |> follow_run(run)
       |> push_event("push-hash", %{"hash" => "log"})}
    end
  end
end
