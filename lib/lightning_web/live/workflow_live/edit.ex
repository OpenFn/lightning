defmodule LightningWeb.WorkflowLive.Edit do
  @moduledoc false
  use LightningWeb, :live_view

  alias Lightning.Policies.ProjectUsers
  alias Lightning.Policies.Permissions
  alias Lightning.Workflows
  alias Lightning.Workflows.Workflow
  alias Lightning.Jobs.Job
  alias LightningWeb.Components.Form
  alias LightningWeb.WorkflowNewLive.WorkflowParams

  import LightningWeb.WorkflowLive.Components

  on_mount {LightningWeb.Hooks, :project_scope}

  attr :changeset, :map, required: true
  attr :project_user, :map, required: true

  def follow_run(attempt_run) do
    send(self(), {:follow_run, attempt_run})
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(
        base_url:
          ~p"/projects/#{assigns.project}/w/#{assigns.workflow.id || "new"}",
        workflow_form: to_form(assigns.changeset)
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
              <Heroicons.lock_closed
                :if={!@can_edit_job}
                class="w-5 h-5 place-self-center text-gray-300"
              />
              <Form.submit_button
                class=""
                phx-disable-with="Saving..."
                disabled={!@can_edit_job or !@changeset.valid?}
                form="workflow-form"
              >
                Save
              </Form.submit_button>
            </div>
          </.with_changes_indicator>
        </LayoutComponents.header>
      </:header>
      <div class="relative h-full flex" id={"workflow-edit-#{@workflow.id}"}>
        <div
          phx-hook="WorkflowEditor"
          class="grow"
          id={"editor-#{@workflow.id}"}
          phx-update="ignore"
        >
          <%!-- Before Editor component has mounted --%>
          <div class="flex place-content-center h-full cursor-wait">
            <.box_loader />
          </div>
        </div>
        <%!-- Job Edit View --%>
        <div class="flex-none" id="job-editor-pane">
          <div
            :if={@selected_job && @selection_mode == "expand"}
            class="fixed left-0 top-0 right-0 bottom-0 m-8 hidden inset-0 z-50
            bg-white fixed inset-0 z-10 overflow-y-auto rounded-lg shadow-xl"
            phx-mounted={fade_in()}
            phx-remove={fade_out()}
          >
            <LightningWeb.WorkflowLive.JobView.job_edit_view
              job={@selected_job}
              current_user={@current_user}
              project={@project}
              socket={@socket}
              on_run={&follow_run/1}
              follow_run_id={@follow_run_id}
              close_url={
                "#{@base_url}?s=#{@selected_job.id}"
              }
              form={single_inputs_for(@workflow_form, :jobs, @selected_job.id)}
            >
              <:footer>
                <.with_changes_indicator changeset={@changeset}>
                  <div class="flex flex-row gap-2">
                    <Heroicons.lock_closed
                      :if={!@can_edit_job}
                      class="w-5 h-5 place-self-center text-gray-300"
                    />
                    <Form.submit_button
                      class=""
                      phx-disable-with="Saving..."
                      disabled={!@can_edit_job or !@changeset.valid?}
                      form="workflow-form"
                    >
                      Save
                    </Form.submit_button>
                  </div>
                </.with_changes_indicator>
              </:footer>
            </LightningWeb.WorkflowLive.JobView.job_edit_view>
          </div>
        </div>
        <.form
          :let={f}
          id="workflow-form"
          for={@workflow_form}
          phx-submit="save"
          phx-hook="SubmitViaCtrlS"
          phx-change="validate"
        >
          <.single_inputs_for
            :let={{jf, has_child_edges}}
            :if={@selected_job}
            form={f}
            field={:jobs}
            id={@selected_job.id}
          >
            <.panel
              title={
                input_value(jf, :name)
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
                editable={@can_edit_job}
                form={jf}
                project_user={@project_user}
              />
              <:footer>
                <div class="flex flex-row">
                  <.link
                    patch={"#{@base_url}?s=#{@selected_job.id}&m=expand"}
                    class="inline-flex items-center rounded-md bg-white px-3.5 py-2.5 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                  >
                    <Heroicons.code_bracket class="w-4 h-4 -ml-0.5" />
                  </.link>
                  <div class="grow flex justify-end">
                    <label>
                      <Common.button
                        color="red"
                        phx-click="delete_node"
                        phx-value-id={@selected_job.id}
                        disabled={!@can_edit_job or has_child_edges}
                      >
                        Delete
                      </Common.button>
                    </label>
                  </div>
                </div>
              </:footer>
            </.panel>
          </.single_inputs_for>
          <.single_inputs_for
            :let={tf}
            :if={@selected_trigger}
            form={f}
            field={:triggers}
            id={@selected_trigger.id}
          >
            <.panel
              id={"trigger-pane-#{@selected_trigger.id}"}
              cancel_url={@base_url}
              title={
                input_value(tf, :type)
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
                  disabled={!@can_edit_job}
                  webhook_url={webhook_url(@selected_trigger)}
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
            form={f}
            field={:edges}
            id={@selected_edge.id}
          >
            <.panel id={"edge-pane-#{@selected_edge.id}"} cancel_url="?" title="Edge">
              <div class="w-auto h-full" id={"edge-pane-#{@workflow.id}"}>
                <!-- Show only the currently selected one -->
                <.edge_form
                  form={ef}
                  disabled={!@can_edit_job}
                  cancel_url={
                    ~p"/projects/#{@project.id}/w/#{@workflow.id || "new"}"
                  }
                />
              </div>
            </.panel>
          </.single_inputs_for>
        </.form>
      </div>
    </LayoutComponents.page_content>
    """
  end

  defp single_inputs_for(form, field, id) do
    form
    |> inputs_for(field)
    |> Enum.find(&(Ecto.Changeset.get_field(&1.source, :id) == id))
  end

  defp single_inputs_for(%{field: :jobs} = assigns) do
    form = assigns[:form]

    has_child_edges = form.source |> has_child_edges?(assigns[:id])

    forms =
      form
      |> inputs_for(assigns[:field])
      |> Enum.filter(&(Ecto.Changeset.get_field(&1.source, :id) == assigns[:id]))

    assigns = assigns |> assign(forms: forms, has_child_edges: has_child_edges)

    ~H"""
    <%= for f <- @forms do %>
      <%= render_slot(@inner_block, {f, @has_child_edges}) %>
    <% end %>
    """
  end

  defp single_inputs_for(assigns) do
    form = assigns[:form]

    forms =
      form
      |> inputs_for(assigns[:field])
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
          can_edit_job:
            Permissions.can?(ProjectUsers, :edit_job, current_user, project_user)
        )

      {:error, _} ->
        socket
        |> put_flash(:error, "You are not authorized to perform this action.")
        |> push_redirect(to: ~p"/projects/#{project.id}/w")
    end)
  end

  def authorize(%{assigns: %{live_action: :edit}} = socket) do
    %{project_user: project_user, current_user: current_user} = socket.assigns

    can_edit_job =
      Permissions.can?(ProjectUsers, :edit_job, current_user, project_user)

    socket
    |> assign(can_edit_job: can_edit_job)
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> authorize()
     |> assign(
       active_menu_item: :projects,
       expanded_job: nil,
       follow_run_id: nil,
       page_title: "",
       selected_edge: nil,
       selected_job: nil,
       selected_trigger: nil,
       selection_mode: nil,
       workflow: nil,
       workflow_params: %{},
       selection_params: %{"s" => nil, "m" => nil}
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     apply_action(socket, socket.assigns.live_action, params)
     |> apply_selection_params(params)}
  end

  def apply_action(socket, :new, _params) do
    if socket.assigns.workflow do
      socket
    else
      socket
      |> assign_workflow(%Workflow{
        project_id: socket.assigns.project.id,
        name: Lightning.Name.generate()
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
            :triggers,
            :edges,
            jobs: [:credential]
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
      can_edit_job: can_edit_job
    } = socket.assigns

    with true <- can_edit_job || :not_authorized,
         true <- !has_child_edges?(changeset, id) || :has_child_edges do
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
       |> push_patch(
         to:
           ~p"/projects/#{socket.assigns.project}/w/#{socket.assigns.workflow}",
         replace: true
       )
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
         |> put_flash(:error, "Delete all descendant jobs first.")}
    end
  end

  def handle_event("validate", %{"workflow" => params}, socket) do
    {:noreply, handle_new_params(socket, params)}
  end

  def handle_event("save", params, socket) do
    %{workflow_params: initial_params, can_edit_job: can_edit_job} =
      socket.assigns

    if can_edit_job do
      next_params =
        case params do
          %{"workflow" => params} ->
            WorkflowParams.apply_form_params(
              socket.assigns.workflow_params,
              params
            )

          %{} ->
            socket.assigns.workflow_params
        end

      socket = socket |> apply_params(next_params)

      socket =
        Lightning.Repo.insert_or_update(socket.assigns.changeset)
        |> case do
          {:ok, workflow} ->
            socket
            |> assign_workflow(workflow)
            |> put_flash(:info, "Workflow saved")

          {:error, changeset} ->
            socket
            |> assign_changeset(changeset)
            |> mark_validated()
            |> put_flash(:error, "Workflow could not be saved")
        end
        |> push_patches_applied(initial_params)

      {:noreply, socket}
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

    {:reply, %{patches: patches}, socket |> apply_selection_params()}
  end

  def handle_event("copied_to_clipboard", _, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Copied webhook URL to clipboard")}
  end

  @impl true
  def handle_info({"form_changed", %{"workflow" => params}}, socket) do
    {:noreply, handle_new_params(socket, params)}
  end

  def handle_info({:follow_run, attempt_run}, socket) do
    {:noreply, socket |> assign(follow_run_id: attempt_run.run_id)}
  end

  defp has_child_edges?(workflow_changeset, job_id) do
    workflow_changeset
    |> Ecto.Changeset.get_assoc(:edges, :struct)
    |> Enum.filter(&(&1.source_job_id == job_id))
    |> Enum.any?()
  end

  defp handle_new_params(socket, params) do
    %{workflow_params: initial_params, can_edit_job: can_edit_job} =
      socket.assigns

    if can_edit_job do
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
    # Build a new changeset from the new params
    changeset =
      socket.assigns.workflow
      |> Workflow.changeset(
        params
        |> set_default_adaptors()
        |> Map.put("project_id", socket.assigns.project.id)
      )

    socket |> assign_changeset(changeset)
  end

  defp apply_selection_params(socket, params) do
    socket
    |> assign(
      selection_params:
        params |> Map.take(["s", "m"]) |> Enum.into(%{"s" => nil, "m" => nil})
    )
    |> apply_selection_params()
  end

  defp apply_selection_params(socket) do
    socket.assigns.selection_params
    |> case do
      # Nothing is selected
      %{"s" => nil} ->
        socket |> unselect_all()

      # Attempt to select the given item, possibly with a mode (such as `expand`)
      %{"s" => selected_id, "m" => mode} ->
        case find_item_in_changeset(socket.assigns.changeset, selected_id) do
          [type, selected] ->
            socket |> select_node({type, selected}, mode)

          nil ->
            socket |> unselect_all()
        end
    end
    |> maybe_unfollow_run()
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

  defp select_node(socket, {type, value}, selection_mode) do
    case type do
      :jobs ->
        socket
        |> assign(selected_job: value, selected_trigger: nil, selected_edge: nil)

      :triggers ->
        socket
        |> assign(selected_job: nil, selected_trigger: value, selected_edge: nil)

      :edges ->
        socket
        |> assign(selected_job: nil, selected_trigger: nil, selected_edge: value)
    end
    |> assign(selection_mode: selection_mode)
  end

  defp maybe_unfollow_run(socket) do
    if changed?(socket, :selected_job) do
      socket |> assign(follow_run_id: nil)
    else
      socket
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
          {:halt, [field, job |> Lightning.Repo.preload(:credential)]}

        item ->
          {:halt, [field, item]}
      end
    end)
  end

  defp mark_validated(socket) do
    socket
    |> assign(changeset: socket.assigns.changeset |> Map.put(:action, :validate))
  end

  defp box_loader(assigns) do
    ~H"""
    <span class="inline-block top-[50%] w-10 h-10 relative border-4
                 border-gray-400 animate-spin-pause">
      <span class="align-top inline-block w-full bg-gray-400 animate-fill-up"></span>
    </span>
    """
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
end
