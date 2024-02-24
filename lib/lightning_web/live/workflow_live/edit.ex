defmodule LightningWeb.WorkflowLive.Edit do
  @moduledoc false
  use LightningWeb, {:live_view, container: {:div, []}}

  import LightningWeb.Components.NewInputs
  import LightningWeb.WorkflowLive.Components

  alias Lightning.Invocation
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects
  alias Lightning.Runs
  alias Lightning.Runs.Events.DataclipUpdated
  alias Lightning.Runs.Events.RunUpdated
  alias Lightning.Runs.Events.StepCompleted
  alias Lightning.Workflows
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkOrders
  alias LightningWeb.Components.Form
  alias LightningWeb.WorkflowLive.Helpers
  alias LightningWeb.WorkflowNewLive.WorkflowParams

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
        save_and_run_disabled: save_and_run_disabled?(assigns)
      )

    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:title>
            <.workflow_name_field form={@workflow_form} />
          </:title>
          <.with_changes_indicator changeset={@changeset}>
            <div class="flex flex-row gap-2">
              <.icon
                :if={!@can_edit_workflow}
                name="hero-lock-closed"
                class="w-5 h-5 place-self-center text-gray-300"
              />
              <Form.submit_button
                class=""
                phx-disable-with="Saving..."
                disabled={!@can_edit_workflow or !@changeset.valid?}
                form="workflow-form"
              >
                Save
              </Form.submit_button>
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
              "fixed left-0 top-0 right-0 bottom-0 m-8 flex-wrap",
              "hidden opacity-0",
              "bg-white inset-0 z-30 overflow-hidden rounded-lg drop-shadow-[0_35px_35px_rgba(0,0,0,0.25)]"
            ]}
            phx-mounted={fade_in()}
            phx-remove={fade_out()}
          >
            <LightningWeb.WorkflowLive.JobView.job_edit_view
              job={@selected_job}
              current_user={@current_user}
              project={@project}
              socket={@socket}
              follow_run_id={@follow_run && @follow_run.id}
              close_url={
                "#{@base_url}?s=#{@selected_job.id}"
              }
              form={single_inputs_for(@workflow_form, :jobs, @selected_job.id)}
            >
              <:collapsible_panel
                id={"manual-job-#{@selected_job.id}"}
                panel_title="Input"
              >
                <LightningWeb.WorkflowLive.ManualWorkorder.component
                  id={"manual-job-#{@selected_job.id}"}
                  form={@manual_run_form}
                  dataclips={@selectable_dataclips}
                  disabled={!@can_run_workflow}
                  project={@project}
                  admin_contacts={@admin_contacts}
                  can_edit_data_retention={@can_edit_data_retention}
                  follow_run_id={@follow_run && @follow_run.id}
                  show_wiped_dataclip_selector={@show_wiped_dataclip_selector}
                />
              </:collapsible_panel>
              <:footer>
                <div class="flex flex-row gap-x-2">
                  <.save_is_blocked_error :if={
                    editor_is_empty(@workflow_form, @selected_job)
                  }>
                    The step can't be blank
                  </.save_is_blocked_error>

                  <.icon
                    :if={!@can_edit_workflow}
                    name="hero-lock-closed"
                    class="w-5 h-5 place-self-center text-gray-300"
                  />
                  <div id="run-buttons" class="inline-flex rounded-md shadow-sm">
                    <.button
                      id="save-and-run"
                      phx-hook="DefaultRunViaCtrlEnter"
                      {if step_retryable?(@step, @manual_run_form, @selectable_dataclips), do:
                        [type: "button", "phx-click": "rerun", "phx-value-run_id": @follow_run.id, "phx-value-step_id": @step.id],
                      else:
                          [type: "submit", form: @manual_run_form.id]}
                      class={[
                        "relative inline-flex items-center",
                        step_retryable?(
                          @step,
                          @manual_run_form,
                          @selectable_dataclips
                        ) && "rounded-r-none"
                      ]}
                      disabled={
                        @save_and_run_disabled ||
                          processing(@follow_run) ||
                          selected_dataclip_wiped?(
                            @manual_run_form,
                            @selectable_dataclips
                          )
                      }
                    >
                      <%= if processing(@follow_run) do %>
                        <.icon
                          name="hero-arrow-path-mini"
                          class="w-4 h-4 animate-spin mr-1"
                        /> Processing
                      <% else %>
                        <%= if step_retryable?(@step, @manual_run_form, @selectable_dataclips) do %>
                          <.icon name="hero-arrow-path-mini" class="w-4 h-4 mr-1" />
                          Rerun from here
                        <% else %>
                          <.icon name="hero-play-solid" class="w-4 h-4 mr-1" />
                          Create New Work Order
                        <% end %>
                      <% end %>
                    </.button>
                    <div
                      :if={
                        step_retryable?(
                          @step,
                          @manual_run_form,
                          @selectable_dataclips
                        )
                      }
                      class="relative -ml-px block"
                    >
                      <.button
                        type="button"
                        class="rounded-l-none pr-1 pl-1 focus:ring-inset"
                        id="option-menu-button"
                        aria-expanded="true"
                        aria-haspopup="true"
                        disabled={@save_and_run_disabled}
                        phx-click={show_dropdown("create-new-work-order")}
                      >
                        <span class="sr-only">Open options</span>
                        <svg
                          class="h-5 w-5"
                          viewBox="0 0 20 20"
                          fill="currentColor"
                          aria-hidden="true"
                        >
                          <path
                            fill-rule="evenodd"
                            d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
                            clip-rule="evenodd"
                          />
                        </svg>
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
                          class={[
                            "hidden absolute right-0 bottom-9 z-10 mb-2 w-max",
                            "rounded-md bg-white px-4 py-2 text-sm font-semibold",
                            "text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                          ]}
                          form={@manual_run_form.id}
                          disabled={@save_and_run_disabled}
                        >
                          <.icon name="hero-play-solid" class="w-4 h-4 mr-1" />
                          Create New Work Order
                        </button>
                      </div>
                    </div>
                  </div>
                  <.with_changes_indicator changeset={@changeset}>
                    <Form.submit_button
                      class=""
                      phx-disable-with="Saving..."
                      disabled={!@can_edit_workflow or !@changeset.valid?}
                      form="workflow-form"
                    >
                      Save
                    </Form.submit_button>
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
        <%= if @selected_job do %>
          <.live_component
            id="new-credential-modal"
            module={LightningWeb.CredentialLive.FormComponent}
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
        <% end %>
        <.form
          id="workflow-form"
          for={@workflow_form}
          phx-submit="save"
          phx-hook="SaveViaCtrlS"
          phx-change="validate"
        >
          <input type="hidden" name="_ignore_me" />
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
              cancel_url={@base_url}
            >
              <!-- Show only the currently selected one -->
              <.job_form
                on_change={&send_form_changed/1}
                editable={@can_edit_workflow}
                form={jf}
                project_user={@project_user}
              />
              <:footer>
                <div class="flex flex-row">
                  <div class="flex items-center">
                    <.expand_job_editor
                      base_url={@base_url}
                      job={@selected_job}
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
                          !@can_edit_workflow or @has_child_edges or @is_first_job or
                            @has_steps
                        }
                        tooltip={
                          deletion_tooltip_message(
                            @can_edit_workflow,
                            @has_child_edges,
                            @is_first_job,
                            @has_steps
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
              cancel_url={@base_url}
              title={
                Phoenix.HTML.Form.input_value(tf, :type)
                |> to_string()
                |> then(fn
                  "" -> "New Trigger"
                  "webhook" -> "Webhook Trigger"
                  "cron" -> "Cron Trigger"
                end)
              }
            >
              <div class="w-auto h-full" id={"trigger-pane-#{@workflow.id}"}>
                <!-- Show only the currently selected one -->
                <.trigger_form
                  form={tf}
                  on_change={&send_form_changed/1}
                  disabled={!@can_edit_workflow}
                  can_write_webhook_auth_method={@can_write_webhook_auth_method}
                  webhook_url={webhook_url(@selected_trigger)}
                  selected_trigger={@selected_trigger}
                  action={@live_action}
                  cancel_url={
                    ~p"/projects/#{@project.id}/w/#{@workflow.id || "new"}"
                  }
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
            <.panel id={"edge-pane-#{@selected_edge.id}"} cancel_url="?" title="Path">
              <div class="w-auto h-full" id={"edge-pane-#{@workflow.id}"}>
                <!-- Show only the currently selected one -->
                <.edge_form
                  form={ef}
                  disabled={!@can_edit_workflow}
                  cancel_url={
                    ~p"/projects/#{@project.id}/w/#{@workflow.id || "new"}"
                  }
                />
              </div>
            </.panel>
          </.single_inputs_for>
        </.form>

        <.live_component
          :if={
            @live_action == :edit && @can_write_webhook_auth_method &&
              @selected_trigger
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

  defp deletion_tooltip_message(
         can_edit_job,
         has_child_edges,
         is_first_job,
         has_steps
       ) do
    cond do
      !can_edit_job ->
        "You are not authorized to delete this step."

      has_child_edges ->
        "You can't delete a step that other downstream steps depend on."

      is_first_job ->
        "You can't delete the only step of a workflow."

      has_steps ->
        "You can't delete a step with associated history while it's protected by your data retention period. (Workflow 'snapshots' are coming. For now, disable the incoming edge to prevent the job from running.)"

      true ->
        nil
    end
  end

  defp expand_job_editor(assigns) do
    is_empty = editor_is_empty(assigns.form, assigns.job)

    button_base_classes =
      ~w(
        inline-flex items-center rounded-md bg-white px-3.5 py-2.5 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset hover:bg-gray-50)

    button_classes =
      button_base_classes ++
        if is_empty,
          do: ~w(ring-red-300),
          else: ~w(ring-gray-300)

    assigns = assign(assigns, is_empty: is_empty, button_classes: button_classes)

    ~H"""
    <.link patch={"#{@base_url}?s=#{@job.id}&m=expand"} class={@button_classes}>
      <.icon name="hero-code-bracket-mini" class="w-4 h-4 text-grey-400" />
    </.link>

    <.save_is_blocked_error :if={@is_empty}>
      The step can't be blank
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
        |> push_redirect(to: ~p"/projects/#{project.id}/w")
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
    {:ok,
     socket
     |> authorize()
     |> assign(
       active_menu_item: :overview,
       expanded_job: nil,
       follow_run: nil,
       step: nil,
       manual_run_form: nil,
       page_title: "",
       selected_edge: nil,
       selected_job: nil,
       selected_trigger: nil,
       selection_mode: nil,
       query_params: %{"s" => nil, "m" => nil, "a" => nil},
       workflow: nil,
       workflow_name: "",
       workflow_params: %{},
       selected_credential_type: nil,
       show_wiped_dataclip_selector: false,
       admin_contacts: Projects.list_project_admin_emails(assigns.project.id)
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     apply_action(socket, socket.assigns.live_action, params)
     |> apply_query_params(params)
     |> maybe_show_manual_run()}
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
    |> assign(page_title: "New Workflow")
  end

  def apply_action(socket, :edit, %{"id" => workflow_id}) do
    case socket.assigns.workflow do
      %{id: ^workflow_id} ->
        socket

      _ ->
        # TODO we shouldn't be calling Repo from here
        workflow =
          Workflows.get_workflow(workflow_id)
          |> Lightning.Repo.preload([
            :edges,
            triggers: Trigger.with_auth_methods_query(),
            jobs:
              {Workflows.jobs_ordered_subquery(),
               [:credential, steps: Invocation.Query.any_step()]}
          ])

        socket |> assign_workflow(workflow) |> assign(page_title: workflow.name)
    end
  end

  @impl true
  def handle_event("get-initial-state", _params, socket) do
    {:noreply,
     socket
     |> push_event("current-workflow-params", %{
       workflow_params: socket.assigns.workflow_params
     })}
  end

  def handle_event("delete_node", %{"id" => id}, socket) do
    %{
      changeset: changeset,
      workflow_params: initial_params,
      can_edit_workflow: can_edit_workflow,
      has_child_edges: has_child_edges,
      is_first_job: is_first_job,
      has_steps: has_steps
    } = socket.assigns

    with true <- can_edit_workflow || :not_authorized,
         true <- !has_child_edges || :has_child_edges,
         true <- !is_first_job || :is_first_job,
         true <- !has_steps || :has_steps do
      edges_to_delete =
        Ecto.Changeset.get_assoc(changeset, :edges, :struct)
        |> Enum.filter(&(&1.target_job_id == id))

      next_params =
        Map.update!(initial_params, "edges", fn edges ->
          edges
          |> Enum.reject(fn edge ->
            edge["id"] in Enum.map(edges_to_delete, & &1.id)
          end)
        end)
        |> Map.update!("jobs", &Enum.reject(&1, fn job -> job["id"] == id end))

      {:noreply,
       socket
       |> apply_params(next_params)
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
         |> put_flash(:error, "You can't delete the first step of a workflow.")}

      :has_steps ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "You can't delete a step that has already been ran."
         )}
    end
  end

  def handle_event("validate", %{"workflow" => params}, socket) do
    {:noreply, handle_new_params(socket, params)}
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
    %{
      project: project,
      workflow_params: initial_params,
      can_edit_workflow: can_edit_workflow
    } =
      socket.assigns

    if can_edit_workflow do
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
        socket = socket |> apply_params(next_params)

      Lightning.Repo.insert_or_update(changeset)
      |> case do
        {:ok, workflow} ->
          {:noreply,
           socket
           |> assign_workflow(workflow)
           |> put_flash(:info, "Workflow saved")
           |> push_patches_applied(initial_params)
           |> on_new_navigate_to_edit(project, workflow)}

        {:error, changeset} ->
          {:noreply,
           socket
           |> assign_changeset(changeset)
           |> mark_validated()
           |> put_flash(:error, "Workflow could not be saved")
           |> push_patches_applied(initial_params)}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action.")}
    end
  end

  def handle_event("push-change", %{"patches" => patches}, socket) do
    # Apply the incoming patches to the current workflow params producing a new
    # set of params.
    {:ok, params} =
      WorkflowParams.apply_patches(socket.assigns.workflow_params, patches)

    socket = socket |> apply_params(params)

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

  def handle_event("toggle_wiped_dataclip_selector", _, socket) do
    {:noreply, update(socket, :show_wiped_dataclip_selector, fn val -> !val end)}
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

  # The retry_from_run event is for creating a new run for an existing work
  # order, just like clicking "rerun from here" on the history page.

  @impl true
  def handle_event(
        "rerun",
        %{"run_id" => run_id, "step_id" => step_id},
        socket
      ) do
    if socket.assigns.can_run_workflow do
      case Lightning.Repo.update(%{socket.assigns.changeset | action: :update}) do
        {:ok, workflow} ->
          {:ok, run} =
            WorkOrders.retry(run_id, step_id,
              created_by: socket.assigns.current_user
            )

          Runs.subscribe(run)

          {:noreply, socket |> assign_workflow(workflow) |> follow_run(run)}

        {:error, changeset} ->
          {
            :noreply,
            socket
            |> assign_changeset(changeset)
            |> mark_validated()
            |> put_flash(:error, "Workflow could not be saved")
          }
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action.")}
    end
  end

  # The manual_run_submit event is for create a new work order from a dataclip and
  # a job.
  def handle_event("manual_run_submit", %{"manual" => params}, socket) do
    %{
      project: project,
      selected_job: selected_job,
      current_user: current_user,
      workflow_params: workflow_params,
      can_edit_workflow: can_edit_workflow,
      can_run_workflow: can_run_workflow
    } = socket.assigns

    socket = socket |> apply_params(workflow_params)

    if can_run_workflow && can_edit_workflow do
      Helpers.save_and_run(
        socket.assigns.changeset,
        params,
        project: project,
        selected_job: selected_job,
        created_by: current_user
      )
    else
      {:error, :unauthorized}
    end
    |> case do
      {:ok, %{workorder: workorder, workflow: workflow}} ->
        %{runs: [run]} = workorder

        Runs.subscribe(run)

        {:noreply,
         socket
         |> assign_workflow(workflow)
         |> follow_run(run)}

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

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "You are not authorized to perform this action.")}
    end
  end

  @impl true
  def handle_info({"form_changed", %{"workflow" => params}}, socket) do
    {:noreply, handle_new_params(socket, params)}
  end

  def handle_info({:forward, mod, opts}, socket) do
    send_update(mod, opts)
    {:noreply, socket}
  end

  def handle_info(%DataclipUpdated{dataclip: dataclip}, socket) do
    dataclip = Invocation.get_dataclip_details!(dataclip.id)

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

  def handle_info(%{}, socket), do: {:noreply, socket}

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
            Invocation.get_step_for_run_and_job(
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
    |> assign(show_wiped_dataclip_selector: is_map(step_dataclip))
  end

  defp get_selected_dataclip(run, job_id) do
    dataclip = Invocation.get_dataclip_for_run_and_job(run.id, job_id)

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
    socket
    |> assign(manual_run_form: to_form(changeset, id: "manual_run_form"))
  end

  defp save_and_run_disabled?(attrs) do
    case attrs do
      %{manual_run_form: nil} ->
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

    parent_form.impl.to_form(parent_form.source, parent_form, field_name, [])
    |> Enum.find(fn f -> Ecto.Changeset.get_field(f.source, :id) == job.id end)
    |> Map.get(:source)
    |> Map.get(:errors)
    |> Keyword.has_key?(:body)
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

  defp has_steps?(job) do
    !Enum.empty?(job.steps)
  end

  defp get_filtered_edges(workflow_changeset, filter_func) do
    workflow_changeset
    |> Ecto.Changeset.get_assoc(:edges, :struct)
    |> Enum.filter(filter_func)
  end

  defp handle_new_params(socket, params) do
    %{workflow_params: initial_params, can_edit_workflow: can_edit_workflow} =
      socket.assigns

    if can_edit_workflow do
      next_params =
        WorkflowParams.apply_form_params(socket.assigns.workflow_params, params)

      socket
      |> apply_params(next_params)
      |> mark_validated()
      |> push_patches_applied(initial_params)
    else
      socket
      |> put_flash(:error, "You are not authorized to perform this action.")
    end
  end

  defp webhook_url(trigger) do
    trigger
    |> case do
      %{type: :webhook, id: id} ->
        Routes.webhooks_url(LightningWeb.Endpoint, :create, [id])

      _ ->
        nil
    end
  end

  defp send_form_changed(params) do
    send(self(), {"form_changed", params})
  end

  defp assign_workflow(socket, workflow) do
    socket
    |> assign(workflow: workflow)
    |> apply_params(socket.assigns.workflow_params)
  end

  defp apply_params(socket, params) do
    changeset =
      socket.assigns.workflow
      |> Workflow.changeset(
        params
        |> set_default_adaptors()
        |> Map.put("project_id", socket.assigns.project.id)
      )

    socket |> assign_changeset(changeset)
  end

  defp apply_query_params(socket, params) do
    socket
    |> assign(
      query_params:
        params
        |> Map.take(["s", "m", "a"])
        |> Enum.into(%{"s" => nil, "m" => nil, "a" => nil})
    )
    |> apply_query_params()
  end

  defp apply_query_params(socket) do
    socket.assigns.query_params
    |> case do
      # Nothing is selected
      %{"s" => nil} ->
        socket |> unselect_all()

      # Try to select the given item, possibly with a mode (such as `expand`)
      %{"s" => selected_id, "m" => mode} ->
        case find_item_in_changeset(socket.assigns.changeset, selected_id) do
          [type, selected] ->
            socket
            |> set_selected_node(type, selected, mode)

          nil ->
            socket |> unselect_all()
        end
    end
    |> maybe_follow_run(socket.assigns.query_params)
  end

  defp assign_changeset(socket, changeset) do
    # Prepare a new set of workflow params from the changeset
    workflow_params = changeset |> WorkflowParams.to_map()

    socket
    |> assign(
      changeset: changeset,
      workflow_params: workflow_params
    )
  end

  defp push_patches_applied(socket, initial_params) do
    next_params = socket.assigns.workflow_params

    patches = WorkflowParams.to_patches(initial_params, next_params)

    socket
    |> push_event("patches-applied", %{patches: patches})
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
    |> assign(selected_job: nil, selected_trigger: nil, selected_edge: nil)
    |> assign(selection_mode: nil)
  end

  defp set_selected_node(socket, type, value, selection_mode) do
    case type do
      :jobs ->
        socket
        |> assign(
          has_steps: has_steps?(value),
          has_child_edges: has_child_edges?(socket.assigns.changeset, value.id),
          is_first_job: first_job?(socket.assigns.changeset, value.id),
          selected_job: value,
          selected_trigger: nil,
          selected_edge: nil
        )

      :triggers ->
        socket
        |> assign(selected_job: nil, selected_trigger: value, selected_edge: nil)

      :edges ->
        socket
        |> assign(selected_job: nil, selected_trigger: nil, selected_edge: value)
    end
    |> assign(selection_mode: selection_mode)
  end

  defp follow_run(socket, run) do
    %{query_params: query_params, project: project, workflow: workflow} =
      socket.assigns

    params = query_params |> Map.put("a", run.id) |> Enum.into([])

    socket
    |> push_patch(to: ~p"/projects/#{project}/w/#{workflow}?#{params}")
  end

  defp maybe_follow_run(socket, query_params) do
    case query_params do
      %{"a" => run_id} when is_binary(run_id) ->
        run = Runs.get(run_id)

        step =
          Invocation.get_step_for_run_and_job(
            run_id,
            socket.assigns.selected_job.id
          )

        Runs.subscribe(run)

        socket |> assign(follow_run: run, step: step)

      _ ->
        socket |> assign(follow_run: nil)
    end
  end

  # find the changeset for the selected item
  # it could be an edge, a job or a trigger
  defp find_item_in_changeset(changeset, id) do
    [:jobs, :triggers, :edges]
    |> Enum.reduce_while(nil, fn field, _ ->
      Ecto.Changeset.get_assoc(changeset, field, :struct)
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

  defp on_new_navigate_to_edit(socket, %{id: project_id}, %{id: workflow_id}) do
    if socket.assigns.live_action == :new do
      socket
      |> push_navigate(to: ~p"/projects/#{project_id}/w/#{workflow_id}")
    else
      socket
    end
  end
end
