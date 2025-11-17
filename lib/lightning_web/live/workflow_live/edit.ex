defmodule LightningWeb.WorkflowLive.Edit do
  @moduledoc false
  use LightningWeb, {:live_view, container: {:div, []}}

  import LightningWeb.Components.NewInputs
  import LightningWeb.Components.Icons
  import LightningWeb.WorkflowLive.Components
  import React

  alias Lightning.Accounts
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
  alias Lightning.VersionControl
  alias Lightning.Workflows
  alias Lightning.Workflows.Events.WorkflowUpdated
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Presence
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.WorkflowTemplate
  alias Lightning.WorkflowTemplates
  alias Lightning.WorkOrders
  alias LightningWeb.UiMetrics
  alias LightningWeb.WorkflowLive.Helpers
  alias LightningWeb.WorkflowLive.NewManualRun
  alias LightningWeb.WorkflowNewLive.WorkflowParams
  alias Phoenix.LiveView.JS

  require Lightning.Run
  require Logger

  on_mount {LightningWeb.Hooks, :project_scope}

  attr :selection, :string, required: false
  attr :aiAssistantId, :string, required: false
  attr :showAiAssistant, :boolean, required: false
  attr :canEditWorkflow, :boolean, required: false
  attr :snapshotVersionTag, :string, required: false
  attr :aiAssistantEnabled, :boolean, required: false
  attr :liveAction, :string, required: false

  jsx("assets/js/workflow-editor/WorkflowEditor.tsx")
  jsx("assets/js/workflow-store/WorkflowStore.tsx")

  attr :job_id, :string
  jsx("assets/js/manual-run-panel/ManualRunPanel.tsx")

  attr :job_id, :string
  attr :job_title, :string
  attr :cancel_url, :string
  attr :back_url, :string
  attr :is_edge, :boolean
  jsx("assets/js/panel/panels/WorkflowRunPanel.tsx")

  attr :changeset, :map, required: true
  attr :project_user, :map, required: true

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(
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
            <div class="flex gap-2 items-center">
              {@page_title}

              <LightningWeb.Components.Common.snapshot_version_chip
                id="canvas-workflow-version"
                version={@snapshot_version_tag}
                tooltip={
                  if @snapshot_version_tag == "latest",
                    do: "This is the latest version of this workflow",
                    else:
                      "You are viewing a snapshot of this workflow that was taken on #{Lightning.Helpers.format_date(@snapshot.inserted_at, "%F at %T")}"
                }
              />
              
    <!-- Add collaborative editor toggle (beaker icon only) -->
              <.link
                :if={
                  show_collaborative_editor_toggle?(
                    @current_user,
                    @snapshot_version_tag
                  )
                }
                navigate={
                  if @live_action == :new do
                    ~p"/projects/#{@project.id}/w/new/collaborate"
                  else
                    ~p"/projects/#{@project.id}/w/#{@workflow.id}/collaborate"
                  end
                }
                class="inline-flex items-center justify-center p-1 text-primary-600 hover:text-primary-700 hover:bg-primary-50 rounded transition-colors"
                phx-hook="Tooltip"
                data-placement="bottom"
                aria-label="Switch to collaborative editor (experimental)"
              >
                <.icon name="hero-beaker" class="h-4 w-4" />
              </.link>

              <LightningWeb.WorkflowLive.Components.online_users
                id="canvas-online-users"
                presences={@presences}
                current_user={@current_user}
                prior_user={@prior_user_presence.user}
              />
              <div :if={
                @snapshot_version_tag != "latest" && @can_edit_workflow &&
                  !@show_new_workflow_panel
              }>
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
            </div>
          </:title>

          <.button
            :if={@snapshot_version_tag != "latest"}
            id={"version-switcher-button-#{@workflow.id}"}
            type="button"
            theme="primary"
            phx-click="switch-version"
            phx-value-type="commit"
            class="mr-4"
          >
            Switch to latest version
          </.button>

          <.with_changes_indicator
            :if={@snapshot_version_tag == "latest" && !@show_new_workflow_panel}
            changeset={@changeset}
          >
            <div class="flex flex-row gap-2">
              <.icon
                :if={!@can_edit_workflow}
                name="hero-lock-closed"
                class="w-5 h-5 place-self-center text-gray-300"
              />
              <div class="flex flex-row m-auto gap-2">
                <.input
                  id="workflow"
                  type="toggle"
                  name="workflow_state"
                  disabled={@sending_ai_message}
                  value={Helpers.workflow_enabled?(@changeset)}
                  tooltip={Helpers.workflow_state_tooltip(@changeset)}
                  on_click="toggle_workflow_state"
                />
                <div>
                  <.settings_icon
                    :if={!@show_new_workflow_panel}
                    changeset={@changeset}
                    selection_mode={@selection_mode}
                    base_url={@base_url}
                    query_params={@query_params}
                    show_workflow_ai_chat={@show_workflow_ai_chat}
                    workflow_chat_session_id={@workflow_chat_session_id}
                    job_chat_session_id={@job_chat_session_id}
                  />
                </div>
                <.offline_indicator />
              </div>
              <.run_workflow_button
                base_url={@base_url}
                show_workflow_ai_chat={@show_workflow_ai_chat}
                workflow_chat_session_id={@workflow_chat_session_id}
                job_chat_session_id={@job_chat_session_id}
                query_params={@query_params}
                trigger_id={
                  if is_list(@workflow_params["triggers"]) and
                       @workflow_params["triggers"] != [] do
                    hd(@workflow_params["triggers"])["id"]
                  else
                    ""
                  end
                }
                ,
                sending_ai_message={@sending_ai_message}
              />
              <.save_workflow_button
                id="top-bar-save-workflow-btn"
                changeset={@changeset}
                can_edit_workflow={@can_edit_workflow}
                snapshot_version_tag={@snapshot_version_tag}
                has_presence_priority={@has_presence_edit_priority}
                sending_ai_message={@sending_ai_message}
                project_repo_connection={@project_repo_connection}
                dropdown_position={:bottom}
              />
            </div>
          </.with_changes_indicator>
        </LayoutComponents.header>
      </:header>
      <.WorkflowStore react-id="workflow-mount" />
      <div id="workflow-to-yaml" class="h-full flex" phx-hook="WorkflowToYAML">
        <.live_component
          :if={@show_new_workflow_panel}
          id={@new_workflow_panel_id}
          ai_assistant_component_id={@new_workflow_ai_assistant_id}
          module={LightningWeb.WorkflowLive.NewWorkflowComponent}
          workflow={@workflow}
          project={@project}
          selected_method={@method || "template"}
          base_url={@base_url}
          chat_session_id={@workflow_chat_session_id}
          query_params={@query_params}
          user={@current_user}
          can_edit={@can_edit_workflow}
          class="transition-all duration-300 ease-in-out"
        />
        <div
          class={"relative h-full flex grow transition-all duration-300 ease-in-out overflow-hidden #{if @show_workflow_ai_chat, do: "w-[30%]", else: ""}"}
          id={"workflow-edit-#{@workflow.id}"}
        >
          <.live_component
            :if={@show_workflow_ai_chat}
            id={@workflow_ai_chat_id}
            ai_assistant_component_id={@workflow_ai_assistant_id}
            module={LightningWeb.WorkflowLive.WorkflowAiChatComponent}
            workflow={@workflow}
            workflow_code={@workflow_code_with_ids}
            project={@project}
            base_url={@base_url}
            query_params={@query_params}
            chat_session_id={@workflow_chat_session_id}
            user={@current_user}
            can_edit={@can_edit_workflow}
            class="transition-all duration-300 ease-in-out"
          />
          <.selected_template_label
            :if={@selected_template && @show_new_workflow_panel}
            template={@selected_template}
            class="transition-all duration-300 ease-in-out"
          />
          <.canvas_placeholder_card :if={@show_canvas_placeholder} />
          <div class="flex-none" id="job-editor-pane">
            <div
              :if={@selected_job && @selection_mode == "expand"}
              class={[
                "fixed left-0 top-0 right-0 bottom-0 flex-wrap",
                "hidden opacity-0",
                "bg-white inset-0 z-45 overflow-hidden drop-shadow-[0_35px_35px_rgba(0,0,0,0.25)]"
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
                      <:tab hash="aichat">
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
                      <div class="grow flex flex-col p-2 min-h-0 h-full">
                        <.ManualRunPanel
                          :if={@selection_mode === "expand"}
                          job_id={@selected_job.id}
                        />
                      </div>
                    </:panel>
                    <:panel hash="aichat" class="h-full">
                      <div class="grow min-h-0 h-full text-sm">
                        <.live_component
                          module={LightningWeb.AiAssistant.Component}
                          mode={:job}
                          can_edit={@can_edit_workflow}
                          project={@project}
                          user={@current_user}
                          chat_session_id={@job_chat_session_id}
                          code={nil}
                          query_params={@query_params}
                          base_url={@base_url}
                          action={if(@job_chat_session_id, do: :show, else: :new)}
                          callbacks={%{}}
                          selected_job={@selected_job}
                          follow_run={@follow_run}
                          id={@job_ai_assistant_id_fn.(@selected_job.id)}
                        />
                      </div>
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
                      disabled={
                        job_deleted?(@selected_job, @workflow) || @sending_ai_message
                      }
                      version={@snapshot_version_tag}
                    />

                    <.save_is_blocked_error :if={is_empty}>
                      {error_message}
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
                      sending_ai_message={@sending_ai_message}
                      snapshot_version_tag={@snapshot_version_tag}
                    />
                    <.with_changes_indicator changeset={@changeset}>
                      <.save_workflow_button
                        id="inspector-save-workflow-btn"
                        changeset={@changeset}
                        can_edit_workflow={@can_edit_workflow}
                        snapshot_version_tag={@snapshot_version_tag}
                        has_presence_priority={@has_presence_edit_priority}
                        sending_ai_message={@sending_ai_message}
                        project_repo_connection={@project_repo_connection}
                        dropdown_position={:top}
                      />
                    </.with_changes_indicator>
                  </div>
                </:footer>
              </LightningWeb.WorkflowLive.JobView.job_edit_view>
            </div>
          </div>

          <.WorkflowEditor
            :if={!@show_canvas_placeholder}
            react-portal-target="workflow-mount"
            selection={
              if @selected_job || @selected_trigger || @selected_edge,
                do: (@selected_job || @selected_trigger || @selected_edge).id,
                else: nil
            }
            showAiAssistant={@show_workflow_ai_chat}
            aiAssistantId={@workflow_ai_chat_id}
            canEditWorkflow={@can_edit_workflow}
            snapshotVersionTag={@snapshot_version_tag}
            aiAssistantEnabled={@ai_assistant_enabled}
            liveAction={Atom.to_string(@live_action)}
          />

          <.live_component
            :if={@selected_job && @can_edit_workflow && @show_job_credential_modal}
            id="new-credential-modal"
            module={LightningWeb.CredentialLive.CredentialFormComponent}
            action={:new}
            credential_type={nil}
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
            oauth_client={nil}
            oauth_clients={@oauth_clients}
            projects={[]}
            project={@project}
            on_save={
              fn credential ->
                form = single_inputs_for(@workflow_form, :jobs, @selected_job.id)

                params =
                  LightningWeb.Utils.build_params_for_field(
                    form,
                    :project_credential_id,
                    credential.project_credentials |> Enum.at(0) |> Map.get(:id)
                  )

                send_form_changed(params)
              end
            }
            on_modal_close={JS.push("toggle_job_credential_modal")}
            can_create_project_credential={@can_edit_workflow}
            return_to={
              Helpers.build_url(assigns, [Helpers.param("s", @selected_job.id)])
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
          <.live_component
            :if={@project_repo_connection && @show_github_sync_modal}
            id="github-sync-modal"
            module={LightningWeb.WorkflowLive.GithubSyncModal}
            current_user={@current_user}
            project_repo_connection={@project_repo_connection}
          />
          <.form
            :if={@selection_mode != "expand"}
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
              cancel_url={close_url(assigns, nil, :unselect)}
            >
              <.workflow_settings
                can_edit_run_settings={@can_edit_run_settings}
                project_id={@workflow.project_id}
                code_view_url={
                  Helpers.build_url(assigns, Helpers.code_view_params())
                }
                project_concurrency_disabled={@workflow.project.concurrency == 1}
                sending_ai_message={@sending_ai_message}
                max_concurrency={@max_concurrency}
                form={@workflow_form}
              />
            </.panel>

            <.single_inputs_for
              :let={{jf}}
              :if={@selected_job && @selection_mode != "workflow_input"}
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
                data-testid={"job-pane-#{jf.index}"}
                cancel_url={close_url(assigns, :selected_job, :unselect)}
                class="hidden"
                phx-mounted={fade_in()}
                phx-remove={fade_out()}
              >
                <.job_form
                  on_change={&send_form_changed/1}
                  editable={
                    is_nil(@workflow.deleted_at) && @can_edit_workflow &&
                      @snapshot_version_tag == "latest" &&
                      @has_presence_edit_priority && !@sending_ai_message
                  }
                  form={jf}
                  project={@project}
                />
                <:footer>
                  <div class="flex flex-row">
                    <div class="flex items-center gap-3">
                      <.expand_job_editor
                        base_url={@base_url}
                        snapshot_lock_version={@snapshot && @snapshot.lock_version}
                        snapshot_version_tag={@snapshot_version_tag}
                        job={@selected_job}
                        selected_run={@selected_run}
                        query_params={@query_params}
                        form={@workflow_form}
                        show_workflow_ai_chat={@show_workflow_ai_chat}
                        workflow_chat_session_id={@workflow_chat_session_id}
                        job_chat_session_id={@job_chat_session_id}
                        sending_ai_message={@sending_ai_message}
                      />
                      <.button_link
                        patch={
                          Helpers.build_url(
                            assigns,
                            Helpers.workflow_input_params(@selected_job.id)
                          )
                        }
                        type="button"
                        disabled={@sending_ai_message}
                        theme="primary"
                      >
                        Run
                      </.button_link>
                    </div>
                    <div class="grow flex justify-end">
                      <label>
                        <.button
                          id="delete-job-button"
                          phx-click="delete_node"
                          phx-value-id={@selected_job.id}
                          theme="danger"
                          disabled={
                            (!is_nil(@workflow.deleted_at) or !@can_edit_workflow or
                               @has_child_edges or @is_first_job or
                               @snapshot_version_tag != "latest") ||
                              !@has_presence_edit_priority || @sending_ai_message
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
                          Delete
                        </.button>
                      </label>
                    </div>
                  </div>
                </:footer>
              </.panel>
            </.single_inputs_for>
            <.single_inputs_for
              :let={tf}
              :if={@selected_trigger && @selection_mode != "workflow_input"}
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
                  |> render_trigger_title()
                }
              >
                <.trigger_form
                  form={tf}
                  on_change={&send_form_changed/1}
                  disabled={
                    (!is_nil(@workflow.deleted_at) or !@can_edit_workflow or
                       @snapshot_version_tag != "latest") ||
                      !@has_presence_edit_priority || @sending_ai_message
                  }
                  can_write_webhook_auth_method={@can_write_webhook_auth_method}
                  selected_trigger={@selected_trigger}
                  action={@live_action}
                  cancel_url={close_url(assigns, :selected_trigger, :unselect)}
                />
                <:footer>
                  <div class="flex flex-row justify-between">
                    <div class="flex items-center">
                      <.input
                        type="toggle"
                        field={tf[:enabled]}
                        disabled={
                          (!is_nil(@workflow.deleted_at) or !@can_edit_workflow or
                             @snapshot_version_tag != "latest") ||
                            !@has_presence_edit_priority || @sending_ai_message
                        }
                        label="Enabled"
                      />
                    </div>
                    <.button_link
                      patch={
                        Helpers.build_url(
                          assigns,
                          Helpers.workflow_input_params(@selected_trigger.id)
                        )
                      }
                      disabled={@sending_ai_message}
                      type="button"
                      theme="primary"
                    >
                      <.icon name="hero-play-solid" class="w-4 h-4" /> Run
                    </.button_link>
                  </div>
                </:footer>
              </.panel>
            </.single_inputs_for>
            <.single_inputs_for
              :let={ef}
              :if={@selected_edge && @selection_mode != "workflow_input"}
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
                <.edge_form
                  form={ef}
                  disabled={
                    (!is_nil(@workflow.deleted_at) or !@can_edit_workflow or
                       @snapshot_version_tag != "latest") ||
                      !@has_presence_edit_priority || @sending_ai_message
                  }
                  cancel_url={close_url(assigns, :selected_edge, :unselect)}
                />
                <:footer>
                  <div class="flex flex-row">
                    <div class="flex items-center">
                      <%= if ef[:source_trigger_id].value do %>
                        <p class="text-sm text-gray-500">
                          This path will be active if its trigger is enabled
                        </p>
                      <% else %>
                        <.input
                          type="toggle"
                          field={ef[:enabled]}
                          disabled={
                            (!is_nil(@workflow.deleted_at) or !@can_edit_workflow or
                               @snapshot_version_tag != "latest") ||
                              !@has_presence_edit_priority || @sending_ai_message
                          }
                          label="Enabled"
                        />
                      <% end %>
                    </div>
                    <div class="grow flex justify-end">
                      <label>
                        <%= unless ef[:source_trigger_id].value do %>
                          <.button
                            id="delete-edge-button"
                            theme="danger"
                            data-confirm="Are you sure you want to delete this path?"
                            phx-click="delete_edge"
                            phx-value-id={ef[:id].value}
                            disabled={
                              (((!is_nil(@workflow.deleted_at) or !@can_edit_workflow or
                                   @snapshot_version_tag != "latest") ||
                                  !@has_presence_edit_priority) or
                                 ef[:source_trigger_id].value) || @sending_ai_message
                            }
                          >
                            Delete Path
                          </.button>
                        <% end %>
                      </label>
                    </div>
                  </div>
                </:footer>
              </.panel>
            </.single_inputs_for>
            <div
              :if={@selection_mode == "workflow_input"}
              class="flex flex-col h-120"
            >
              <.WorkflowRunPanel
                job_id={
                  if @selected_job do
                    @selected_job.id
                  else
                    hd(@workflow_params["jobs"])["id"]
                  end
                }
                job_title={
                  if @selected_job do
                    @selected_job.name
                  else
                    "Trigger"
                  end
                }
                is_edge={
                  if @selected_edge do
                    true
                  else
                    false
                  end
                }
                cancel_url={
                  Helpers.build_url(assigns, Helpers.params_without_mode_selection())
                }
                back_url={
                  if @selected_job do
                    Helpers.build_url(
                      assigns,
                      [Helpers.param("s", @selected_job.id)] ++
                        Helpers.orthogonal_params()
                    )
                  else
                    Helpers.build_url(
                      assigns,
                      Helpers.params_without_mode_selection()
                    )
                  end
                }
              />
            </div>
          </.form>

          <.panel
            :if={@selection_mode == "code"}
            title={
              if @publish_template,
                do: "Publish Workflow as Template",
                else: "Workflow as Code"
            }
            id={"workflow-code-#{@workflow.id}"}
            class="hidden min-w-lg"
            phx-mounted={fade_in()}
            phx-remove={fade_out()}
            cancel_url={close_url(assigns, nil, :unselect)}
          >
            <div
              :if={!@workflow_code && !@publish_template}
              id="workflow-code-loader"
              class="relative text-xs @md:text-base p-12 text-center bg-slate-700 font-mono text-slate-200"
            >
              <.text_ping_loader>
                Stand by
              </.text_ping_loader>
            </div>
            <.textarea_element
              :if={@workflow_code && !@publish_template}
              id="workflow-code-viewer"
              name="workflow-code"
              value={@workflow_code}
              rows="18"
              disabled={true}
              class="font-mono proportional-nums text-slate-200 bg-slate-700 resize-none text-nowrap overflow-x-auto"
            />
            <.form
              :let={f}
              :if={@workflow_code && @publish_template}
              for={@workflow_template_changeset}
              id="workflow-template-form"
              phx-change="validate"
              phx-submit="save"
            >
              <div class="container mx-auto space-y-4 bg-white">
                <.input
                  type="text"
                  field={f[:name]}
                  label="Name"
                  required={true}
                  placeholder="A descriptive name for your template"
                />

                <.input
                  type="textarea"
                  field={f[:description]}
                  label="Description"
                  rows="6"
                  class="bg-white text-slate-900"
                  placeholder="A detailed description of what this template does"
                />

                <div class="space-y-4">
                  <.input
                    type="tag"
                    field={f[:tags]}
                    label="Tags"
                    placeholder="Separate tags with commas (,)"
                  />
                </div>
              </div>
            </.form>
            <:footer>
              <div :if={!@publish_template} class="flex flex-row justify-end gap-2">
                <.button
                  theme="secondary"
                  id="download-workflow-code-btn"
                  data-target="#workflow-code-viewer"
                  data-content-type="text/yaml"
                  data-file-name={String.replace(@workflow.name || "workflow"," ", "-") <> ".yaml"}
                  phx-hook="DownloadText"
                >
                  Download
                </.button>
                <.button
                  theme="secondary"
                  id="copy-workflow-code-btn"
                  data-to="#workflow-code-viewer"
                  phx-hook="Copy"
                  class="min-w-[6rem]"
                >
                  Copy Code
                </.button>
                <.button
                  :if={@current_user.support_user}
                  theme="primary"
                  id="publish-template-btn"
                  phx-click="publish_template"
                  class="min-w-[8rem]"
                  disabled={@changeset.changes |> Enum.any?() || @sending_ai_message}
                  tooltip={
                    if @changeset.changes |> Enum.any?(),
                      do:
                        "You must save your workflow first before #{if @has_workflow_template?, do: "updating", else: "publishing"} a template.",
                      else: nil
                  }
                >
                  {if @has_workflow_template?,
                    do: "Update Template",
                    else: "Publish Template"}
                </.button>
              </div>
              <div :if={@publish_template} class="sm:flex sm:flex-row-reverse gap-3">
                <.button
                  type="submit"
                  theme="primary"
                  form="workflow-template-form"
                  disabled={
                    !@workflow_template_changeset.valid? || @sending_ai_message
                  }
                >
                  {if @has_workflow_template?,
                    do: "Update Template",
                    else: "Publish Template"}
                </.button>
                <.button
                  id="cancel-template-publish"
                  type="button"
                  phx-click="cancel_publish_template"
                  theme="secondary"
                >
                  Back
                </.button>
              </div>
            </:footer>
          </.panel>

          <.live_component
            :if={
              @live_action == :edit && @can_write_webhook_auth_method &&
                @selected_trigger && @snapshot_version_tag == "latest" &&
                @active_modal == :webhook_auth_method
            }
            module={LightningWeb.WorkflowLive.WebhookAuthMethodModalComponent}
            id="manage_webhook_auth_methods"
            action={:index}
            trigger={@selected_trigger}
            project={@project}
            current_user={@current_user}
            on_close={JS.push("close_active_modal")}
            on_save={
              fn trigger_or_auth_method ->
                send(self(), {:webhook_auth_method_updated, trigger_or_auth_method})
              end
            }
            return_to={
              Helpers.build_url(assigns, [Helpers.param("s", @selected_trigger.id)])
            }
          />
        </div>
      </div>
    </LayoutComponents.page_content>
    """
  end

  defp run_buttons(assigns) do
    ~H"""
    <div id="run-buttons" class="inline-flex rounded-md shadow-xs">
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
      theme="primary"
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
          assigns.snapshot_version_tag != "latest" || @sending_ai_message
      }
    >
      <%= if processing(@follow_run) do %>
        <.icon name="hero-arrow-path" class="w-4 h-4 animate-spin mr-1" /> Processing
      <% else %>
        <%= if step_retryable?(@step, @manual_run_form, @selectable_dataclips) do %>
          <.icon name="hero-play-mini" class="w-4 h-4 mr-1" /> Run (retry)
        <% else %>
          <.icon name="hero-play-mini" class="w-4 h-4 mr-1" /> Run
        <% end %>
      <% end %>
    </.button>
    """
  end

  defp create_new_work_order_dropdown(assigns) do
    ~H"""
    <div class="relative -ml-px block">
      <.button
        type="button"
        theme="primary"
        class="h-full rounded-l-none pr-1 pl-1"
        id="option-menu-button"
        aria-expanded="true"
        aria-haspopup="true"
        disabled={
          @save_and_run_disabled || @sending_ai_message ||
            @snapshot_version_tag != "latest"
        }
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
        <.button
          phx-click-away={hide_dropdown("create-new-work-order")}
          phx-hook="AltRunViaCtrlShiftEnter"
          id="create-new-work-order"
          type="submit"
          form={@manual_run_form.id}
          theme="secondary"
          class="hidden absolute right-0 bottom-9 z-10 mb-2 w-max"
          disabled={@save_and_run_disabled || @snapshot_version_tag != "latest"}
        >
          <.icon name="hero-play-solid" class="w-4 h-4 mr-1" /> Run (New Work Order)
        </.button>
      </div>
    </div>
    """
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
          {@label}
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

    params =
      Helpers.with_params(
        s: assigns.job.id,
        m: "expand",
        a: [
          value: fn a, _ -> a.selected_run end,
          when: fn a, _ -> a.selected_run != nil end
        ],
        v: [
          value: fn a, _ -> a.snapshot_lock_version end,
          when: fn a, _ -> a.snapshot_version_tag != "latest" end
        ]
      )

    url = Helpers.build_url(assigns, params)

    assigns =
      assign(assigns,
        is_empty: is_empty,
        error_message: error_message,
        url: url
      )

    ~H"""
    <.button_link
      id={"open-inspector-#{@job.id}"}
      patch={@url}
      disabled={@sending_ai_message}
      theme="primary"
    >
      Edit
    </.button_link>

    <.save_is_blocked_error :if={@is_empty}>
      {@error_message}
    </.save_is_blocked_error>
    """
  end

  defp save_is_blocked_error(assigns) do
    ~H"""
    <span class="flex items-center font-medium text-sm text-red-600 ml-1 mr-4 gap-x-1.5">
      <.icon name="hero-exclamation-circle" class="h-5 w-5" />
      {render_slot(@inner_block)}
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
      {render_slot(@inner_block, {f})}
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
      {render_slot(@inner_block, f)}
    <% end %>
    """
  end

  defp with_changes_indicator(assigns) do
    ~H"""
    <div class="relative">
      <div
        :if={@changeset.changes |> Enum.any?()}
        class="absolute -m-1 rounded-full bg-danger-500 w-3 h-3 top-0 right-0 z-10"
        data-is-dirty="true"
      >
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :id, :string, required: true
  attr :can_edit_workflow, :boolean, required: true
  attr :changeset, Ecto.Changeset, required: true
  attr :snapshot_version_tag, :string, required: true
  attr :has_presence_priority, :boolean, required: true
  attr :sending_ai_message, :boolean, default: false
  attr :project_repo_connection, :map, required: true
  attr :dropdown_position, :atom, values: [:top, :bottom], required: true

  defp save_workflow_button(assigns) do
    {disabled, tooltip} =
      case assigns do
        %{
          changeset: %{valid?: true, data: %{deleted_at: nil}},
          can_edit_workflow: true,
          snapshot_version_tag: "latest",
          has_presence_priority: true,
          sending_ai_message: false
        } ->
          {false, nil}

        %{changeset: %{data: %{deleted_at: deleted_at}}}
        when is_struct(deleted_at) ->
          {true, "Workflow has been deleted"}

        %{can_edit_workflow: false} ->
          {true, "You do not have permission to edit this workflow"}

        %{sending_ai_message: true} ->
          {true, "AI is currently processing your request"}

        %{changeset: %{valid?: false}} ->
          {true, "You have unresolved errors in your workflow"}

        %{snapshot_version_tag: tag} when tag != "latest" ->
          {true, "You cannot edit an old snapshot of a workflow"}

        _other ->
          {true, nil}
      end

    assigns = assign(assigns, disabled: disabled, tooltip: tooltip)

    ~H"""
    <div class="inline-flex rounded-md shadow-xs z-5">
      <.button
        id={@id}
        phx-disable-with
        disabled={@disabled}
        {if @disabled, do: [], else: ["phx-hook": "InspectorSaveViaCtrlS", "phx-click": JS.push("save")]}
        phx-disconnected={JS.set_attribute({"disabled", ""})}
        tooltip={@tooltip}
        class={
          ["focus:ring-transparent"] ++
            if @project_repo_connection, do: ["rounded-r-none"], else: []
        }
        phx-connected={!@disabled && JS.remove_attribute("disabled")}
        theme="primary"
      >
        Save
      </.button>
      <div :if={@project_repo_connection} class="relative -ml-px block">
        <.button
          type="button"
          class="h-full rounded-l-none pr-1 pl-1"
          id={"#{@id}-save-and-sync-option-menu-button"}
          aria-expanded="true"
          aria-haspopup="true"
          disabled={@disabled}
          phx-click={show_dropdown("#{@id}-save-and-sync")}
          phx-disconnected={JS.set_attribute({"disabled", ""})}
          phx-connected={!@disabled && JS.remove_attribute("disabled")}
          theme="primary"
        >
          <span class="sr-only">Open options</span>
          <.icon name="hero-chevron-down" class="w-4 h-4" />
        </.button>
        <div
          role="menu"
          aria-orientation="vertical"
          aria-labelledby={"#{@id}-save-and-sync-option-menu-button"}
          tabindex="-1"
        >
          <.button
            phx-click-away={hide_dropdown("#{@id}-save-and-sync")}
            id={"#{@id}-save-and-sync"}
            type="button"
            phx-click="toggle_github_sync_modal"
            theme="secondary"
            class={[
              "hidden absolute right-0 z-10 w-max",
              if(@dropdown_position == :top, do: "bottom-9 mb-2"),
              if(@dropdown_position == :bottom, do: "top-9 mt-2")
            ]}
            disabled={@disabled}
            phx-hook="OpenSyncModalViaCtrlShiftS"
          >
            Save & Sync
          </.button>
        </div>
      </div>
    </div>
    """
  end

  defp settings_icon(assigns) do
    base_icon_class = "w-5 h-5 place-self-center cursor-pointer"

    class =
      if workflow_settings_errors?(assigns.changeset) do
        base_icon_class <> " text-danger-500 hover:text-danger-400"
      else
        base_icon_class <> " text-slate-500 hover:text-slate-400"
      end

    params =
      if assigns.selection_mode == "settings" do
        Helpers.orthogonal_params()
      else
        [Helpers.param("m", "settings")] ++ Helpers.orthogonal_params()
      end

    url = Helpers.build_url(assigns, params)
    assigns = assigns |> assign(:class, class) |> assign(:url, url)

    ~H"""
    <.link patch={@url} class={@class} id="toggle-settings">
      <.icon name="hero-adjustments-vertical" />
    </.link>
    """
  end

  defp selected_template_label(assigns) do
    ~H"""
    <div
      id={"selected-template-label-#{@template.id}"}
      phx-mounted={fade_in()}
      class="absolute z-40 m-4 opacity-75 bg-white/100 border border-gray-200 rounded-lg p-6"
    >
      <div class="flex items-start gap-3 opacity-100">
        <div class="flex-shrink-0">
          <div class="w-10 h-10 rounded-lg ai-bg-gradient flex items-center justify-center">
            <.icon name="hero-document-text" class="w-5 h-5 text-white" />
          </div>
        </div>

        <div class="flex-1 min-w-0">
          <h3 class="text-sm font-medium text-gray-900 tracking-tight leading-tight mb-2">
            {@template.name}
          </h3>
          <p class="text-sm text-gray-600 leading-relaxed">
            {@template.description}
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp canvas_placeholder_card(assigns) do
    ~H"""
    <div class="flex items-center justify-center w-full h-full p-8">
      <div class="max-w-md text-center space-y-6">
        <div class="relative mx-auto w-24 h-24 mb-8">
          <div class="relative ai-bg-gradient rounded-2xl p-6">
            <.icon name="hero-bolt" class="w-12 h-12 text-white" />
          </div>
        </div>
        <div class="space-y-3">
          <h3 class="text-xl font-semibold text-gray-900 dark:text-gray-100">
            Ready for a new workflow?
          </h3>
          <p class="text-gray-600 dark:text-gray-400 leading-relaxed">
            Get started by selecting a template, importing a workflow, or opening a chat with the AI assistant.
          </p>
        </div>
        <p class="text-xs text-gray-400 dark:text-gray-500 mt-6">
          Not sure where to start? Try browsing our template library first.
        </p>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: assigns} = socket) do
    view_only_users_ids =
      assigns.project
      |> view_only_users()
      |> Enum.map(fn pu -> pu.user.id end)

    workflow_ai_chat_id = "workflow-ai-chat-panel"
    new_workflow_panel_id = "new-workflow-panel"

    {:ok,
     socket
     |> authorize()
     |> assign(
       view_only_users_ids: view_only_users_ids,
       active_menu_item: :overview,
       expanded_job: nil,
       ai_assistant_enabled: AiAssistant.enabled?(),
       workflow_chat_session_id: nil,
       job_chat_session_id: nil,
       selected_template: nil,
       follow_run: nil,
       step: nil,
       manual_run_form: nil,
       page_title: "",
       selected_edge: nil,
       selected_job: nil,
       last_selected_job: nil,
       selected_run: nil,
       selected_trigger: nil,
       selection_mode: nil,
       base_url: nil,
       query_params: %{
         "s" => nil,
         "m" => nil,
         "a" => nil,
         "v" => nil,
         "w-chat" => nil,
         "j-chat" => nil,
         "method" => nil
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
       show_new_workflow_panel: assigns.live_action == :new,
       show_canvas_placeholder: assigns.live_action == :new,
       show_workflow_ai_chat: false,
       show_job_credential_modal: false,
       active_modal: nil,
       active_modal_assigns: nil,
       admin_contacts: Projects.list_project_admin_emails(assigns.project.id),
       show_github_sync_modal: false,
       publish_template: false,
       method: nil,
       workflow_code: nil,
       workflow_code_with_ids: nil,
       workflow_ai_chat_id: workflow_ai_chat_id,
       workflow_ai_assistant_id: "#{workflow_ai_chat_id}-assistant",
       new_workflow_panel_id: new_workflow_panel_id,
       new_workflow_ai_assistant_id: "#{new_workflow_panel_id}-assistant",
       job_ai_assistant_id_fn: fn job_id -> "job-#{job_id}-ai-assistant" end,
       ai_assistant_registry: %{},
       sending_ai_message: false,
       project_repo_connection:
         VersionControl.get_repo_connection_for_project(assigns.project.id),
       max_concurrency: assigns.project.concurrency
     )
     |> assign(initial_presence_summary(assigns.current_user))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(
       active_modal: nil,
       active_modal_assigns: nil
     )
     |> apply_action(socket.assigns.live_action, params)
     |> track_user_presence()
     |> apply_query_params(params)
     |> prepare_workflow_template()
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

  defp authorize(%{assigns: %{live_action: :new}} = socket) do
    %{project_user: project_user, current_user: current_user, project: project} =
      socket.assigns

    Permissions.can(ProjectUsers, :create_workflow, current_user, project_user)
    |> then(fn
      :ok ->
        assign_permissions(socket, current_user, project_user)

      {:error, _} ->
        socket
        |> put_flash(:error, "You are not authorized to perform this action.")
        |> push_navigate(to: ~p"/projects/#{project.id}/w")
    end)
  end

  defp authorize(%{assigns: %{live_action: :edit}} = socket) do
    %{project_user: project_user, current_user: current_user} = socket.assigns
    assign_permissions(socket, current_user, project_user)
  end

  defp assign_permissions(socket, current_user, project_user) do
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
        ),
      can_edit_run_settings:
        Permissions.can?(
          ProjectUsers,
          :edit_run_settings,
          current_user,
          project_user
        )
    )
  end

  defp apply_action(socket, :new, params) do
    method = Map.get(params, "method", "template")

    if socket.assigns.workflow do
      socket
    else
      socket
      |> assign_workflow(%Workflow{
        project_id: socket.assigns.project.id,
        id: Ecto.UUID.generate()
      })
    end
    |> assign(page_title: "New Workflow")
    |> assign(method: method)
    |> assign(base_url: ~p"/projects/#{socket.assigns.project}/w/new")
  end

  defp apply_action(socket, :edit, %{"id" => workflow_id} = params) do
    case socket.assigns.workflow do
      %{id: ^workflow_id} ->
        socket
        |> assign(
          base_url:
            ~p"/projects/#{socket.assigns.project}/w/#{socket.assigns.workflow}"
        )

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
          |> assign(
            base_url: ~p"/projects/#{socket.assigns.project}/w/#{workflow}"
          )
        else
          socket
          |> put_flash(:error, "Workflow not found")
          |> push_navigate(to: ~p"/projects/#{socket.assigns.project}/w")
        end
    end
  end

  @impl true
  def handle_event("workflow_editor_metrics_report", params, socket) do
    UiMetrics.log_workflow_editor_metrics(
      socket.assigns.workflow,
      params["metrics"]
    )

    {:noreply, socket}
  end

  def handle_event("get-current-state", _params, socket) do
    run_id = socket.assigns.selected_run

    %{run_steps: run_steps, history: history} =
      get_run_steps_and_history(
        socket.assigns.workflow.id,
        run_id
      )

    # don't forget to send update state of disabled
    {:reply,
     %{
       workflow_params: socket.assigns.workflow_params,
       run_steps: run_steps,
       run_id: run_id,
       history: history
     }, maybe_disable_canvas(socket)}
  end

  def handle_event(
        "search-selectable-dataclips",
        %{"job_id" => job_id, "search_text" => search_text, "limit" => limit} =
          params,
        socket
      ) do
    offset = Map.get(params, "offset")

    case NewManualRun.search_selectable_dataclips(
           job_id,
           search_text,
           limit,
           offset
         ) do
      {:ok,
       %{
         dataclips: dataclips,
         next_cron_run_dataclip_id: next_cron_run_dataclip_id
       }} ->
        {:reply,
         %{
           dataclips: dataclips,
           next_cron_run_dataclip_id: next_cron_run_dataclip_id,
           can_edit_dataclip: socket.assigns.can_edit_workflow
         }, socket}

      {:error, changeset} ->
        {:reply,
         %{
           dataclips: [],
           next_cron_run_dataclip_id: nil,
           errors: LightningWeb.ChangesetJSON.errors(changeset),
           can_edit_dataclip: socket.assigns.can_edit_workflow
         }, socket}
    end
  end

  def handle_event(
        "get-run-step-and-input-dataclip",
        %{"run_id" => run_id, "job_id" => job_id},
        socket
      ) do
    dataclip = Invocation.get_first_dataclip_for_run_and_job(run_id, job_id)
    run_step = Invocation.get_first_step_for_run_and_job(run_id, job_id)

    {:reply, %{dataclip: dataclip, run_step: run_step}, socket}
  end

  def handle_event(
        "update-dataclip-name",
        %{"dataclip_id" => dataclip_id, "name" => name},
        socket
      ) do
    if socket.assigns.can_edit_workflow do
      dataclip = Invocation.get_dataclip!(dataclip_id)
      current_user = socket.assigns.current_user

      case Invocation.update_dataclip_name(dataclip, name, current_user) do
        {:ok, updated_dataclip} ->
          flash =
            if updated_dataclip.name do
              "Label created. Dataclip will be saved permanently"
            else
              "Label deleted. Dataclip will be purged when your retention policy limit is reached"
            end

          {:reply, %{dataclip: updated_dataclip},
           put_flash(socket, :info, flash)}

        {:error, _changeset} ->
          {:reply, %{error: "dataclip name already in use"}, socket}
      end
    else
      {:reply, %{error: "You are not authorized to perform this action"}, socket}
    end
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

  def handle_event("validate", %{"workflow_template" => template_params}, socket) do
    tags =
      template_params["tags"]
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    changeset =
      template_params
      |> Map.merge(%{
        "code" => socket.assigns.workflow_code,
        "workflow_id" => socket.assigns.workflow.id,
        "tags" => tags
      })
      |> then(&WorkflowTemplate.changeset(socket.assigns.workflow_template, &1))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :workflow_template_changeset, changeset)}
  end

  def handle_event("save", %{"workflow_template" => template_params}, socket) do
    %{workflow: workflow, workflow_code: code} = socket.assigns

    tags =
      template_params["tags"]
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    params =
      Map.merge(template_params, %{
        "code" => code,
        "workflow_id" => workflow.id,
        "tags" => tags,
        "positions" => workflow.positions
      })

    case WorkflowTemplates.create_template(params) do
      {:ok, _template} ->
        flash_msg =
          if socket.assigns.has_workflow_template?,
            do: "Workflow template updated.",
            else: "Workflow published as template."

        url_params = [Helpers.param("m", "code")]

        {:noreply,
         socket
         |> put_flash(:info, flash_msg)
         |> push_patch(to: Helpers.build_url(socket.assigns, url_params))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :workflow_template_changeset, changeset)}
    end
  end

  def handle_event("save", params, socket) do
    with {:ok, %{assigns: assigns} = socket} <- save_workflow(socket, params) do
      link_workflow_to_ai_session(assigns)

      flash_msg =
        "Workflow saved successfully." <>
          if assigns.live_action == :new and
               not Helpers.workflow_enabled?(assigns.workflow) do
            " Remember to enable your workflow to run it automatically."
          else
            ""
          end

      updated_socket =
        if assigns.live_action == :new do
          base_url = ~p"/projects/#{assigns.project}/w/#{assigns.workflow}"

          base_socket =
            socket
            |> assign(:base_url, base_url)
            |> assign(:live_action, :edit)
            |> assign(:selected_template, nil)
            |> update(:show_new_workflow_panel, fn _ -> false end)
            |> maybe_disable_canvas()

          final_socket =
            if assigns.query_params["method"] == "ai" do
              base_socket
              |> update(:show_workflow_ai_chat, fn _ -> true end)
            else
              base_socket
            end

          push_event(final_socket, "force-fit", %{})
        else
          socket
        end

      patch_url =
        Helpers.build_url(updated_socket.assigns, Helpers.standard_params())

      {:noreply,
       updated_socket
       |> put_flash(:info, flash_msg)
       |> push_patch(to: patch_url, replace: true)}
    end
  end

  def handle_event("save-and-sync", %{"github_sync" => _} = params, socket) do
    with {:ok, %{assigns: assigns} = socket} <- save_workflow(socket, params) do
      link_workflow_to_ai_session(assigns)

      update_socket =
        if assigns.live_action == :new do
          base_url = ~p"/projects/#{assigns.project}/w/#{assigns.workflow}"

          socket
          |> assign(:base_url, base_url)
          |> assign(:live_action, :edit)
        else
          socket
        end

      patch_url =
        Helpers.build_url(update_socket.assigns, Helpers.standard_params())

      {:noreply,
       update_socket
       |> sync_to_github(params)
       |> push_patch(to: patch_url, replace: true)}
    end
  end

  def handle_event("toggle_github_sync_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_github_sync_modal: !socket.assigns.show_github_sync_modal
     )}
  end

  def handle_event("toggle_job_credential_modal", _params, socket) do
    {:noreply, update(socket, :show_job_credential_modal, fn show -> !show end)}
  end

  def handle_event("push-change", %{"patches" => patches}, socket) do
    params =
      WorkflowParams.apply_patches(socket.assigns.workflow_params, patches)
      |> case do
        {:ok, params} -> params
        {:error, _} -> socket.assigns.workflow_params
      end

    version_type =
      if socket.assigns.snapshot_version_tag == "latest" do
        :workflow
      else
        :snapshot
      end

    socket =
      socket
      |> apply_params(params, version_type)
      |> generate_workflow_code()

    # Calculate the difference between the new params and changes introduced by
    # the changeset/validation.
    patches = WorkflowParams.to_patches(params, socket.assigns.workflow_params)

    {:reply, %{patches: patches}, socket}
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

  def handle_event("toggle-workflow-ai-chat", _params, socket) do
    if socket.assigns.snapshot_version_tag != "latest" do
      {:noreply, socket}
    else
      show_workflow_ai_chat = socket.assigns.show_workflow_ai_chat

      url_params =
        Helpers.with_params(method: [value: "ai", when: !show_workflow_ai_chat])

      {:noreply,
       socket
       |> assign(show_workflow_ai_chat: !show_workflow_ai_chat)
       |> push_patch(to: Helpers.build_url(socket.assigns, url_params))}
    end
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
        %{"run_id" => run_id, "step_id" => step_id} = params,
        socket
      ) do
    case rerun(socket, run_id, step_id, params["via"]) do
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
      workflow_params: workflow_params,
      has_presence_edit_priority: has_presence_edit_priority,
      workflow: workflow,
      manual_run_form: form
    } = socket.assigns

    manual_params = Map.get(params, "manual", %{})
    from_start? = Map.get(params, "from_start", false)
    from_job = Map.get(params, "from_job", nil)

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

    selected_job =
      cond do
        from_start? ->
          get_starting_job(workflow_or_changeset)

        from_job != nil ->
          get_job_by_id(workflow_or_changeset, from_job)

        true ->
          selected_job
      end

    with {:ok, %{workorder: %{runs: [run]}, workflow: workflow}} <-
           manual_run_workflow(
             socket,
             workflow_or_changeset,
             params,
             selected_job
           ) do
      if from_start? || from_job != nil do
        {:noreply,
         socket
         |> push_navigate(to: ~p"/projects/#{project}/runs/#{run}")}
      else
        Runs.subscribe(run)

        snapshot = snapshot_by_version(workflow.id, workflow.lock_version)

        # Get the dataclip for the run
        dataclip = Invocation.get_dataclip_for_run(run.id)

        {:noreply,
         socket
         |> assign_workflow(workflow, snapshot)
         |> follow_run(run)
         |> push_event("push-hash", %{"hash" => "log"})
         |> push_event("manual_run_created", %{dataclip: dataclip})}
      end
    end
  end

  def handle_event("toggle_workflow_state", %{"workflow_state" => state}, socket) do
    if socket.assigns.sending_ai_message do
      {:noreply, socket}
    else
      changeset =
        Workflows.update_triggers_enabled_state(
          socket.assigns.changeset,
          state
        )

      params = WorkflowParams.to_map(changeset)

      {:noreply,
       socket
       |> assign(:changeset, changeset)
       |> handle_new_params(params, :workflow)}
    end
  end

  def handle_event("publish_template", _params, socket) do
    {:noreply, assign(socket, publish_template: true)}
  end

  def handle_event("cancel_publish_template", _params, socket) do
    {:noreply, assign(socket, publish_template: false)}
  end

  def handle_event(
        "workflow_code_generated",
        %{"code" => code, "code_with_ids" => code_with_ids},
        socket
      ) do
    {:noreply,
     assign(socket, workflow_code: code, workflow_code_with_ids: code_with_ids)}
  end

  def handle_event("close_template_tooltip", _params, socket) do
    {:noreply, assign(socket, selected_template: nil)}
  end

  def handle_event("close_active_modal", _params, socket) do
    socket
    |> assign(active_modal: nil, active_modal_assigns: nil)
    |> noreply()
  end

  def handle_event(
        "show_modal",
        %{"target" => "webhook_auth_method"},
        socket
      ) do
    if socket.assigns.can_write_webhook_auth_method do
      socket
      |> assign(
        active_modal: :webhook_auth_method,
        active_modal_assigns: %{}
      )
      |> noreply()
    else
      socket
      |> put_flash(:error, "You are not authorized to perform this action")
      |> noreply()
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

  def handle_info(
        {:webhook_auth_method_updated, _trigger_or_auth_method},
        socket
      ) do
    %{workflow: current_workflow, snapshot: snapshot} = socket.assigns

    updated_workflow = get_workflow_by_id(current_workflow.id)

    socket
    |> assign_workflow(updated_workflow, snapshot)
    |> apply_mode_and_selection()
    |> noreply()
  end

  def handle_info({:form_changed, %{"workflow" => params}}, socket) do
    {:noreply, handle_new_params(socket, params, :workflow)}
  end

  def handle_info({:form_changed, %{"snapshot" => params}}, socket) do
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
    {:noreply, update_presence_summary(socket)}
  end

  @impl true
  def handle_info({:ai_assistant, action, payload}, socket) do
    case action do
      :canvas_state_changed ->
        update_canvas_state(socket, payload)

      :workflow_params_changed ->
        handle_workflow_params_change(socket, payload)

      :message_status_changed ->
        handle_message_status_change(socket, payload)

      :register_component ->
        handle_component_registration(socket, payload)

      :unregister_component ->
        handle_component_unregistration(socket, payload)
    end
  end

  def handle_info(%{}, socket) do
    {:noreply, socket}
  end

  defp get_workflow_by_id(workflow_id) do
    Workflows.get_workflow(workflow_id)
    |> Lightning.Repo.preload([
      :project,
      :edges,
      triggers: Trigger.with_auth_methods_query(),
      jobs:
        {Workflows.jobs_ordered_subquery(),
         [:credential, steps: Invocation.Query.any_step()]}
    ])
  end

  defp snapshot_by_version(workflow_id, version),
    do: Snapshot.get_by_version(workflow_id, version)

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

  defp format_step(step) do
    %{
      id: step.id,
      job_id: step.job_id,
      error_type: step.error_type,
      exit_reason: step.exit_reason,
      started_at: step.started_at,
      finished_at: step.finished_at,
      input_dataclip_id: step.input_dataclip_id
    }
  end

  defp get_workflow_run_history(workflow_id, includes_run_id) do
    WorkOrders.get_workorders_with_runs(workflow_id, includes_run_id)
    |> Enum.map(fn worder ->
      %{
        runs:
          worder.runs
          |> Enum.map(fn run ->
            Map.take(run, [:id, :state, :error_type, :started_at, :finished_at])
          end),
        version: worder.snapshot.lock_version,
        state: worder.state,
        last_activity: worder.last_activity,
        id: worder.id
      }
    end)
  end

  defp get_run_steps_and_history(workflow_id, run_id) do
    empty_resp = %{start_from: nil, steps: [], isTrigger: true, inserted_at: nil}

    run_steps =
      if run_id == nil do
        empty_resp
      else
        Runs.get(run_id, include: [:created_by, :steps])
        |> case do
          nil ->
            empty_resp

          %{
            steps: run_steps,
            starting_trigger_id: trigger_id,
            starting_job_id: job_id
          } =
              data ->
            %{
              start_from: job_id || trigger_id,
              steps: run_steps,
              isTrigger: !!trigger_id,
              inserted_at: data.inserted_at,
              run_by:
                if(is_nil(data.created_by), do: nil, else: data.created_by.email)
            }
        end
      end
      |> Map.update!(:steps, fn steps -> Enum.map(steps, &format_step/1) end)

    history = get_workflow_run_history(workflow_id, run_id)

    %{run_steps: run_steps, history: history}
  end

  defp save_workflow(socket, submitted_params) do
    %{
      workflow_params: initial_params,
      current_user: current_user
    } = socket.assigns

    with :ok <- check_user_can_save_workflow(socket) do
      next_params =
        case submitted_params do
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

          {
            :ok,
            socket
            |> assign(page_title: workflow.name)
            |> assign_workflow(workflow, snapshot)
            |> push_patches_applied(initial_params)
            |> maybe_push_workflow_created(workflow)
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

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           socket
           |> assign_changeset(changeset)
           |> mark_validated()
           |> put_flash(:error, get_error_message(socket))
           |> push_patches_applied(initial_params)}
      end
    end
  end

  defp get_error_message(socket) do
    base_message = "Workflow could not be saved"

    if socket.assigns.live_action == :new &&
         socket.assigns.show_canvas_placeholder do
      "#{base_message}. Please make sure you select a template, or import one, or use the AI assistant to build your workflow"
    else
      base_message
    end
  end

  defp manual_run_workflow(
         socket,
         workflow_or_changeset,
         manual_params,
         selected_job
       ) do
    %{project: project, current_user: current_user} = socket.assigns

    with :ok <- check_user_can_manual_run_workflow(socket) do
      case Helpers.run_workflow(
             workflow_or_changeset,
             manual_params,
             project: project,
             selected_job: selected_job,
             created_by: current_user
           ) do
        {:ok, result} ->
          {:ok, result}

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
        snapshot_version_tag: "latest",
        sending_ai_message: false
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

      %{sending_ai_message: true} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Cannot save while AI is processing"
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

  defp get_job_by_id(%Workflow{} = workflow, job_id) do
    Enum.find(workflow.jobs, fn job -> job.id == job_id end)
  end

  defp get_job_by_id(%Ecto.Changeset{} = workflow_changeset, job_id) do
    workflow_changeset
    |> Ecto.Changeset.get_assoc(:jobs, :struct)
    |> Enum.find(fn job -> job.id == job_id end)
  end

  defp get_starting_job(%Workflow{} = workflow) do
    trigger = hd(workflow.triggers)

    edge =
      Enum.find(workflow.edges, fn edge ->
        edge.source_trigger_id == trigger.id
      end)

    get_job_by_id(workflow, edge.target_job_id)
  end

  defp get_starting_job(%Ecto.Changeset{} = workflow_changeset) do
    trigger =
      workflow_changeset
      |> Ecto.Changeset.get_assoc(:triggers, :struct)
      |> hd()

    edge =
      workflow_changeset
      |> Ecto.Changeset.get_assoc(:edges, :struct)
      |> Enum.find(fn edge ->
        edge.source_trigger_id == trigger.id
      end)

    get_job_by_id(workflow_changeset, edge.target_job_id)
  end

  defp toggle_latest_version(socket) do
    %{
      changeset: prev_changeset,
      workflow: workflow,
      selected_job: selected_job
    } = socket.assigns

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

      if version != "latest" do
        Presence.untrack_user_presence(
          socket.assigns.current_user,
          socket.assigns.workflow,
          self()
        )
      end

      url_params =
        Helpers.to_latest_params()
        |> Enum.reject(fn
          [name: "method", value: _] -> true
          [name: "w-chat", value: _] -> true
          [name: "j-chat", value: _] -> true
          _ -> false
        end)

      socket
      |> assign(changeset: next_changeset)
      |> assign(workflow_params: next_params)
      |> assign(snapshot_version_tag: version)
      |> push_patches_applied(prev_params)
      |> maybe_disable_canvas()
      |> push_patch(to: Helpers.build_url(socket.assigns, url_params))
    end
  end

  defp commit_latest_version(socket) do
    %{changeset: prev_changeset, workflow: workflow} = socket.assigns

    snapshot = snapshot_by_version(workflow.id, workflow.lock_version)
    prev_params = WorkflowParams.to_map(prev_changeset)

    url_params =
      Helpers.orthogonal_params()
      |> Enum.reject(fn
        [name: "method", value: _] -> true
        [name: "w-chat", value: _] -> true
        [name: "j-chat", value: _] -> true
        _ -> false
      end)

    socket
    |> assign_workflow(workflow, snapshot)
    |> push_patches_applied(prev_params)
    |> push_patch(to: Helpers.build_url(socket.assigns, url_params))
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

  defp unselect_all(socket) do
    socket
    |> assign(
      selected_edge: nil,
      selected_job: nil,
      selected_trigger: nil,
      selection_mode: nil
    )
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
          selected_edge: nil
        )

      :edges ->
        socket
        |> assign(
          selected_job: nil,
          selected_trigger: nil,
          selected_edge: value
        )
    end
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

  @spec close_url(map(), atom() | nil, :select | :unselect) :: String.t()
  defp close_url(assigns, selection_type, action) do
    mode_and_selection_params =
      case action do
        :unselect ->
          []

        :select
        when selection_type == :selected_job and is_struct(assigns.selected_job) ->
          [Helpers.param("s", assigns.selected_job.id)]

        _ ->
          []
      end

    Helpers.build_url(
      assigns,
      mode_and_selection_params ++ Helpers.orthogonal_params()
    )
  end

  defp display_switcher(snapshot, workflow) do
    snapshot && snapshot.lock_version != workflow.lock_version
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

  defp workflow_settings_errors?(changeset) do
    errors_keys = Keyword.keys(changeset.errors)
    Enum.any?([:name, :concurrency], &(&1 in errors_keys))
  end

  defp track_user_presence(socket) do
    if connected?(socket) && socket.assigns.snapshot_version_tag == "latest" do
      Presence.track_user_presence(
        socket.assigns.current_user,
        socket.assigns.workflow,
        self()
      )

      update_presence_summary(socket)
    else
      socket
    end
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

  defp update_presence_summary(socket) do
    summary =
      socket.assigns.workflow
      |> Presence.list_presences_for()
      |> Presence.build_presences_summary(socket.assigns)

    assign(socket, summary)
    |> maybe_switch_workflow_version()
    |> maybe_disable_canvas()
  end

  defp view_only_users(project) do
    Lightning.Repo.preload(project, project_users: [:user])
    |> Map.get(:project_users)
    |> Enum.filter(fn pu -> pu.role == :viewer end)
  end

  defp maybe_disable_canvas(socket) do
    %{
      has_presence_edit_priority: has_edit_priority,
      snapshot_version_tag: version,
      can_edit_workflow: can_edit_workflow,
      workflow: workflow,
      show_new_workflow_panel: show_new_workflow_panel
    } = socket.assigns

    disabled =
      !(is_nil(workflow.deleted_at) && has_edit_priority && version == "latest" &&
          can_edit_workflow)

    push_event(socket, "set-disabled", %{
      disabled: show_new_workflow_panel || disabled
    })
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

        body =
          new_manual_run_form_body(
            assigns.manual_run_form,
            job,
            dataclip
          )

        changeset =
          WorkOrders.Manual.new(
            %{dataclip_id: dataclip && dataclip.id, body: body},
            project: socket.assigns.project,
            workflow: socket.assigns.workflow,
            job: socket.assigns.selected_job,
            created_by: socket.assigns.current_user
          )

        selectable_dataclips =
          Invocation.list_dataclips_for_job(%Job{id: job.id})

        socket
        |> assign_manual_run_form(changeset)
        |> assign_dataclips(selectable_dataclips, dataclip)

      _ ->
        socket
    end
  end

  defp assign_manual_run_form(socket, changeset) do
    assign(socket, manual_run_form: to_form(changeset, id: "manual_run_form"))
  end

  defp new_manual_run_form_body(
         prev_manual_run_form,
         selected_job,
         selected_dataclip
       ) do
    prev_job =
      prev_manual_run_form &&
        Ecto.Changeset.get_embed(
          prev_manual_run_form.source,
          :job,
          :struct
        )

    if is_nil(selected_dataclip) and is_struct(prev_job) and
         prev_job.id == selected_job.id do
      Ecto.Changeset.get_change(prev_manual_run_form.source, :body)
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
        form_valid = manual_run_form.source.valid?

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

  defp handle_new_params(socket, params, type, push_patches \\ true) do
    %{workflow_params: initial_params, can_edit_workflow: can_edit_workflow} =
      socket.assigns

    if can_edit_workflow do
      next_params =
        WorkflowParams.apply_form_params(socket.assigns.workflow_params, params)

      updated_socket =
        socket
        |> apply_params(next_params, type)
        |> mark_validated()

      if push_patches do
        push_patches_applied(updated_socket, initial_params)
      else
        updated_socket
      end
    else
      socket
      |> put_flash(:error, "You are not authorized to perform this action.")
    end
  end

  defp assign_workflow(socket, workflow) do
    workflow = Lightning.Repo.preload(workflow, :project)

    alloted_concurrency =
      workflow.project_id
      |> Workflows.list_project_workflows()
      |> Enum.map(fn %{id: workflow_id, concurrency: concurrency} ->
        if workflow_id == workflow.id, do: 0, else: concurrency || 0
      end)
      |> Enum.sum()

    project_concurrency = workflow.project.concurrency || 0

    socket
    |> assign(
      workflow: workflow,
      max_concurrency: max(0, project_concurrency - alloted_concurrency)
    )
    |> apply_params(socket.assigns.workflow_params, :workflow)
  end

  defp assign_workflow(socket, workflow, snapshot) do
    {changeset, version} =
      if snapshot.lock_version == workflow.lock_version do
        {Ecto.Changeset.change(workflow), "latest"}
      else
        {Ecto.Changeset.change(snapshot), String.slice(snapshot.id, 0..6)}
      end

    show_workflow_ai_chat =
      if version == "latest" do
        Map.get(socket.assigns, :show_workflow_ai_chat, false)
      else
        false
      end

    socket
    |> assign(workflow: workflow)
    |> assign(snapshot: snapshot)
    |> assign(snapshot_version_tag: version)
    |> assign(show_workflow_ai_chat: show_workflow_ai_chat)
    |> assign_changeset(changeset)
    |> maybe_disable_canvas()
    |> generate_workflow_code()
  end

  defp apply_query_params(socket, params) do
    socket
    |> assign(
      query_params:
        params
        |> Map.take(["s", "m", "a", "v", "w-chat", "j-chat", "code", "method"])
        |> Enum.into(%{
          "s" => nil,
          "m" => nil,
          "a" => nil,
          "v" => nil,
          "w-chat" => nil,
          "j-chat" => nil,
          "code" => nil,
          "method" => nil
        })
    )
    |> apply_query_params()
  end

  defp apply_query_params(socket) do
    socket
    |> apply_mode_and_selection()
    |> handle_new_workflow_panel()
    |> assign_follow_run(socket.assigns.query_params)
    |> assign_chat_session_id(socket.assigns.query_params)
    |> assign_show_workflow_ai_chat()
  end

  defp apply_mode_and_selection(
         %{assigns: %{query_params: %{"m" => "workflow_input", "s" => s}}} =
           socket
       )
       when not is_nil(s) do
    handle_selection_with_mode(socket, s, "workflow_input")
  end

  defp apply_mode_and_selection(
         %{assigns: %{query_params: %{"m" => "expand", "s" => s}}} = socket
       )
       when not is_nil(s) do
    handle_selection_with_mode(socket, s, "expand")
  end

  defp apply_mode_and_selection(
         %{assigns: %{query_params: %{"m" => "settings"}}} = socket
       ) do
    handle_settings_mode(socket)
  end

  defp apply_mode_and_selection(
         %{assigns: %{query_params: %{"m" => "code"}}} = socket
       ) do
    handle_code_mode(socket)
  end

  defp apply_mode_and_selection(
         %{
           assigns: %{
             query_params: %{"m" => "history", "v" => v, "a" => a, "s" => s}
           }
         } = socket
       )
       when not is_nil(v) do
    handle_run_selection_history(socket, a, v, s)
  end

  defp apply_mode_and_selection(
         %{assigns: %{query_params: %{"s" => s} = params}} = socket
       )
       when not is_nil(s) do
    handle_selection_with_mode(socket, s, params["m"])
  end

  defp apply_mode_and_selection(socket) do
    handle_no_selection(socket)
  end

  defp handle_selection_with_mode(socket, nil, mode) do
    socket
    |> set_mode(
      if mode in ["expand", "workflow_input", "history"], do: mode, else: nil
    )
  end

  defp handle_selection_with_mode(socket, selected_id, mode) do
    case find_item(socket.assigns.changeset, selected_id) do
      [type, selected] ->
        socket
        |> set_selected_node(type, selected)
        |> set_mode(
          if mode in ["expand", "workflow_input", "settings", "history"],
            do: mode,
            else: nil
        )

      nil ->
        socket |> unselect_all()
    end
  end

  defp handle_settings_mode(socket) do
    socket |> unselect_all() |> set_mode("settings")
  end

  defp handle_code_mode(socket) do
    socket
    |> unselect_all()
    |> set_mode("code")
    |> assign(publish_template: false)
  end

  defp handle_no_selection(socket) do
    socket |> unselect_all() |> set_mode(nil)
  end

  defp handle_new_workflow_panel(socket) do
    if socket.assigns.show_new_workflow_panel do
      socket |> unselect_all() |> set_mode(nil)
    else
      socket
    end
  end

  # version_tag will never be nil here
  defp handle_run_selection_history(socket, run_id, version_tag, selected_id) do
    workflow_id = socket.assigns.workflow.id

    %{run_steps: run_steps} =
      get_run_steps_and_history(workflow_id, run_id)

    snapshot = snapshot_by_version(workflow_id, version_tag)

    # pushing the snapshot state before pushing the runs for it
    socket
    |> handle_selection_with_mode(selected_id, "history")
    |> assign(selected_run: run_id)
    |> assign_workflow(socket.assigns.workflow, snapshot)
    |> push_patches_applied(socket.assigns.workflow_params, false)
    |> push_event("patch-runs", %{
      run_id: run_id,
      run_steps: run_steps
    })
    |> maybe_disable_canvas()
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

  defp push_patches_applied(socket, initial_params, inverse \\ true) do
    next_params = socket.assigns.workflow_params

    patches =
      WorkflowParams.to_patches(initial_params, next_params)

    inverse_patches =
      if inverse == true,
        do: WorkflowParams.to_patches(next_params, initial_params),
        else: []

    if length(patches) > 0 do
      socket
      |> push_event("patches-applied", %{
        patches: patches,
        inverse: inverse_patches
      })
      |> generate_workflow_code()
    else
      socket
    end
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

  defp set_mode(socket, mode) do
    if mode in [nil, "expand", "settings", "code", "workflow_input", "history"] do
      socket
      |> assign(selection_mode: mode)
    else
      socket
    end
  end

  defp processing(%{state: state}) do
    !(state in Lightning.Run.final_states())
  end

  defp processing(_run), do: false

  defp follow_run(socket, run) do
    %{changeset: changeset, workflow: workflow, selection_mode: current_mode} =
      socket.assigns

    version = Ecto.Changeset.get_field(changeset, :lock_version)
    mode = current_mode || "expand"

    selection =
      case socket.assigns do
        %{selected_job: %{id: job_id}} -> job_id
        _ -> nil
      end

    params =
      Helpers.with_params(
        a: run.id,
        v: [
          value: version,
          when: fn _, _ -> workflow.lock_version != version end
        ],
        m: [value: mode, when: fn _, _ -> mode != nil end],
        s: [value: selection, when: fn _, _ -> selection != nil end]
      )

    push_patch(socket, to: Helpers.build_url(socket.assigns, params))
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

  defp mark_validated(socket) do
    socket
    |> assign(changeset: socket.assigns.changeset |> Map.put(:action, :validate))
  end

  defp run_workflow_button(assigns) do
    params = Helpers.workflow_input_params(assigns.trigger_id)
    url = Helpers.build_url(assigns, params)
    assigns = assign(assigns, :url, url)

    ~H"""
    <.button_link
      disabled={@sending_ai_message}
      patch={@url}
      type="button"
      theme="primary"
    >
      Run
    </.button_link>
    """
  end

  defp rerun(socket, run_id, step_id, via) do
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
      if via == "job_panel" do
        {:ok, push_navigate(socket, to: ~p"/projects/#{project_id}/runs/#{run}")}
      else
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

  defp job_deleted?(selected_job, workflow) do
    not Enum.any?(workflow.jobs, fn job -> job.id == selected_job.id end)
  end

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

  defp remove_edges_from_params(initial_params, edges_to_delete, id) do
    Map.update!(initial_params, "edges", fn edges ->
      edges
      |> Enum.reject(fn edge ->
        edge["id"] in Enum.map(edges_to_delete, & &1.id)
      end)
    end)
    |> Map.update!("jobs", &Enum.reject(&1, fn job -> job["id"] == id end))
  end

  defp assign_chat_session_id(socket, params) do
    job_chat_session_id =
      if changed?(socket, :selected_job) &&
           not is_nil(socket.assigns[:last_selected_job]) do
        nil
      else
        params["j-chat"]
      end

    socket
    |> assign(
      workflow_chat_session_id: params["w-chat"],
      job_chat_session_id: job_chat_session_id,
      last_selected_job: socket.assigns[:selected_job]
    )
  end

  defp assign_show_workflow_ai_chat(socket) do
    %{
      live_action: live_action,
      query_params: query_params,
      snapshot_version_tag: version
    } = socket.assigns

    show_workflow_ai_chat =
      (live_action == :edit && query_params["method"] == "ai" &&
         version == "latest") ||
        Map.get(socket.assigns, :show_workflow_ai_chat, false)

    assign(socket, show_workflow_ai_chat: show_workflow_ai_chat)
  end

  defp update_canvas_state(socket, payload) do
    show_canvas_placeholder =
      Map.get(
        payload,
        :show_canvas_placeholder,
        socket.assigns.show_canvas_placeholder
      )

    selected_template =
      Map.get(
        payload,
        :show_template_tooltip,
        socket.assigns.selected_template
      )

    sending_ai_message = Map.get(payload, :sending_ai_message, false)

    {:noreply,
     socket
     |> push_event("set-disabled", %{
       disabled: sending_ai_message
     })
     |> assign(
       show_canvas_placeholder: show_canvas_placeholder,
       selected_template: selected_template,
       sending_ai_message: sending_ai_message
     )
     |> then(fn socket ->
       if show_canvas_placeholder do
         assign(socket, :workflow_params, %{})
       else
         socket
       end
     end)}
  end

  defp handle_workflow_params_change(socket, %{"workflow" => incoming_params}) do
    create_action? = socket.assigns.live_action == :new

    {:noreply,
     socket
     |> handle_new_params(incoming_params, :workflow, !create_action?)
     |> push_event("set-disabled", %{disabled: create_action?})
     |> push_event("force-fit", %{})}
  end

  defp handle_component_registration(socket, %{
         component_id: component_id,
         session_id: session_id
       }) do
    registry = socket.assigns.ai_assistant_registry

    if connected?(socket) && !Map.has_key?(registry, session_id) do
      Lightning.subscribe("ai_session:#{session_id}")
    end

    updated_registry = Map.put(registry, session_id, component_id)

    {:noreply, assign(socket, :ai_assistant_registry, updated_registry)}
  end

  defp handle_component_unregistration(socket, %{component_id: component_id}) do
    registry = socket.assigns.ai_assistant_registry

    session_id =
      Enum.find_value(registry, fn {sid, cid} ->
        if cid == component_id, do: sid
      end)

    updated_registry = Map.delete(registry, session_id)

    if session_id && connected?(socket) do
      Lightning.unsubscribe("ai_session:#{session_id}")
    end

    {:noreply, assign(socket, :ai_assistant_registry, updated_registry)}
  end

  defp handle_message_status_change(socket, %{
         status: status,
         session_id: session_id
       }) do
    registry = socket.assigns.ai_assistant_registry

    case Map.get(registry, session_id) do
      nil ->
        {:noreply, socket}

      component_id ->
        send_update(LightningWeb.AiAssistant.Component,
          id: component_id,
          message_status_changed: status
        )

        {:noreply, socket}
    end
  end

  defp link_workflow_to_ai_session(%{
         live_action: :new,
         query_params: %{"method" => "ai", "w-chat" => chat_id},
         workflow: workflow
       })
       when is_binary(chat_id) do
    case Lightning.AiAssistant.get_session(chat_id) do
      %Lightning.AiAssistant.ChatSession{} = session ->
        Lightning.AiAssistant.associate_workflow(session, workflow)

      nil ->
        Logger.warning(
          "Failed to associate workflow with chat session #{chat_id}: not found"
        )
    end
  end

  defp link_workflow_to_ai_session(_assigns), do: :ok

  defp sync_to_github(socket, %{
         "github_sync" => %{"commit_message" => commit_message}
       }) do
    case VersionControl.initiate_sync(
           socket.assigns.project_repo_connection,
           commit_message
         ) do
      :ok ->
        link_to_actions =
          "https://www.github.com/" <>
            socket.assigns.project_repo_connection.repo <> "/actions"

        socket
        |> assign(show_github_sync_modal: false)
        |> put_flash(
          :info,
          %DynamicComponent{
            function: &github_sync_successfull_flash/1,
            args: %{link_to_actions: link_to_actions}
          }
        )

      {:error, _github_error} ->
        put_flash(
          socket,
          :error,
          "Workflow saved but not synced to GitHub. Check the project GitHub connection settings"
        )
    end
  end

  defp prepare_workflow_template(
         %{assigns: %{workflow: workflow, workflow_code: workflow_code}} = socket
       ) do
    template =
      WorkflowTemplates.get_template_by_workflow_id(workflow.id) ||
        %WorkflowTemplate{
          workflow_id: workflow.id,
          tags: []
        }

    changeset =
      WorkflowTemplate.changeset(template, %{
        name: template.name || workflow.name,
        code: workflow_code
      })

    socket
    |> assign(
      workflow_template: template,
      workflow_template_changeset: changeset,
      current_template_tag: nil,
      has_workflow_template?: template.id != nil
    )
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

  defp send_form_changed(params) do
    send(self(), {:form_changed, params})
  end

  defp maybe_push_workflow_created(socket, workflow) do
    if socket.assigns.live_action == :new do
      push_event(socket, "workflow_created", %{id: workflow.id})
    else
      socket
    end
  end

  defp render_trigger_title(trigger_type) do
    case trigger_type do
      "" ->
        "New Trigger"

      "webhook" ->
        "Webhook Trigger"

      "cron" ->
        "Cron Trigger"

      "kafka" ->
        kafka_trigger_title(%{id: "kafka-trigger-title"})

      _ ->
        "Unknown Trigger"
    end
  end

  defp generate_workflow_code(socket) do
    push_event(socket, "generate_workflow_code", %{})
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

  defp show_collaborative_editor_toggle?(user, snapshot_version_tag) do
    Accounts.experimental_features_enabled?(user) &&
      snapshot_version_tag == "latest"
  end
end
