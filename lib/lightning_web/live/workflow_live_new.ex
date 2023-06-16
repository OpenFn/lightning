defmodule LightningWeb.WorkflowNewLive do
  @moduledoc false
  use LightningWeb, :live_view

  alias Lightning.Policies.ProjectUsers
  alias Lightning.Policies.Permissions
  alias Lightning.Workflows
  alias Lightning.Workflows.Workflow
  alias LightningWeb.Components.Form
  alias LightningWeb.WorkflowNewLive.WorkflowParams

  import LightningWeb.WorkflowLive.Components

  on_mount {LightningWeb.Hooks, :project_scope}

  attr :changeset, :map, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header socket={@socket}>
          <:title>
            <.workflow_name_field changeset={@changeset} />
          </:title>
          <Form.submit_button
            class=""
            phx-disable-with="Saving..."
            disabled={!@changeset.valid?}
          >
            Save
          </Form.submit_button>
        </LayoutComponents.header>
      </:header>
      <div class="relative h-full flex">
        <div
          class="grow"
          phx-hook="WorkflowEditor"
          id={"editor-#{@project.id}"}
          data-edit-job-url={~p"/projects/#{@project.id}/w-new/new/j/:job_id"}
          data-edit-trigger-url={
            ~p"/projects/#{@project.id}/w-new/new/t/:trigger_id"
          }
          data-base-url={~p"/projects/#{@project.id}/w-new/#{@workflow.id || "new"}"}
          phx-update="ignore"
        >
          <%!-- Before Editor component has mounted --%> Loading...
        </div>
        <div
          :if={@selected_job}
          class="grow-0 w-1/2 relative min-w-[300px] max-w-[90%]"
          lv-keep-style
        >
          <.resize_component id={"resizer-#{@workflow.id}"} />
          <div class="absolute inset-y-0 left-2 right-0 z-10 resize-x ">
            <div class="w-auto h-full" id={"job-pane-#{@workflow.id}"}>
              <.form
                :let={f}
                for={@changeset}
                phx-submit="save"
                phx-change="validate"
                class="h-full"
              >
                <%= for job_form <- inputs_for(f, :jobs) do %>
                  <!-- Show only the currently selected one -->
                  <.job_form
                    :if={
                      Ecto.Changeset.get_field(job_form.source, :id) ==
                        @selected_job
                        |> Ecto.Changeset.get_field(:id)
                    }
                    on_change={&send_form_changed/1}
                    form={job_form}
                    cancel_url={
                      ~p"/projects/#{@project.id}/w-new/#{@workflow.id || "new"}"
                    }
                  />
                <% end %>
              </.form>
            </div>
          </div>
        </div>
        <div
          :if={@selected_trigger}
          class="grow-0 w-1/2 relative min-w-[300px] max-w-[90%]"
          lv-keep-style
        >
          <.resize_component id={"resizer-#{@workflow.id}"} />
          <div class="absolute inset-y-0 left-2 right-0 z-10 resize-x ">
            <div class="w-auto h-full" id={"trigger-pane-#{@workflow.id}"}>
              <.form
                :let={f}
                for={@changeset}
                phx-submit="save"
                phx-change="validate"
                class="h-full"
              >
                <%= for trigger_form <- inputs_for(f, :triggers) do %>
                  <!-- Show only the currently selected one -->
                  <.trigger_form
                    :if={
                      Ecto.Changeset.get_field(trigger_form.source, :id) ==
                        Ecto.Changeset.get_field(@selected_trigger, :id)
                    }
                    form={trigger_form}
                    on_change={&send_form_changed/1}
                    requires_cron_job={
                      Ecto.Changeset.get_field(trigger_form.source, :type) == :cron
                    }
                    disabled={!@can_edit_job}
                    webhook_url={webhook_url(trigger_form.source)}
                    cancel_url={
                      ~p"/projects/#{@project.id}/w-new/#{@workflow.id || "new"}"
                    }
                  />
                <% end %>
              </.form>
            </div>
          </div>
        </div>
      </div>
    </LayoutComponents.page_content>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.project

    can_edit_job =
      ProjectUsers
      |> Permissions.can(
        :edit_job,
        socket.assigns.current_user,
        project
      )

    {:ok,
     socket
     |> assign(
       project: project,
       selected_job: nil,
       selected_trigger: nil,
       page_title: "",
       active_menu_item: :projects,
       can_edit_job: can_edit_job
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def apply_action(socket, :new, _params) do
    assign(socket,
      page_title: "New Workflow"
    )
    |> assign_workflow(%Workflow{project: socket.assigns.project})
    |> unselect_all()
  end

  def apply_action(socket, :edit, %{"id" => workflow_id}) do
    socket
    |> maybe_assign_workflow(workflow_id)
    |> unselect_all()
    |> assign(page_title: "Edit Workflow")
  end

  def apply_action(socket, :edit_job, %{"id" => workflow_id, "job_id" => job_id}) do
    socket = maybe_assign_workflow(socket, workflow_id)

    job =
      socket.assigns.changeset
      |> Ecto.Changeset.get_change(:jobs, [])
      |> Enum.find(fn changeset ->
        changeset |> Ecto.Changeset.get_field(:id) == job_id
      end)

    socket |> select_node(job: job)
  end

  def apply_action(socket, :edit_trigger, %{
        "id" => workflow_id,
        "trigger_id" => trigger_id
      }) do
    socket = maybe_assign_workflow(socket, workflow_id)

    trigger =
      socket.assigns.changeset
      |> Ecto.Changeset.get_change(:triggers, [])
      |> Enum.find(fn changeset ->
        changeset |> Ecto.Changeset.get_field(:id) == trigger_id
      end)

    socket |> select_node(trigger: trigger)
  end

  @impl true
  def handle_event("get-initial-state", _params, socket) do
    {:reply, socket.assigns.workflow_params, socket}
  end

  def handle_event("validate", %{"workflow" => params}, socket) do
    initial_params = socket.assigns.workflow_params

    next_params =
      WorkflowParams.apply_form_params(socket.assigns.workflow_params, params)

    {:noreply,
     socket
     |> apply_params(next_params)
     |> push_patches_applied(initial_params)}
  end

  def handle_event("save", %{"workflow" => params}, socket) do
    # update the changeset
    # then do the 'normal' insert or update

    initial_params = socket.assigns.workflow_params

    next_params =
      WorkflowParams.apply_form_params(socket.assigns.workflow_params, params)

    socket = socket |> apply_params(next_params)

    socket =
      Lightning.Repo.update(socket.assigns.changeset)
      |> case do
        {:ok, workflow} ->
          socket
          |> assign_workflow(workflow)
          |> put_flash(:info, "Workflow saved")

        {:error, changeset} ->
          socket
          |> assign_changeset(changeset)
          |> put_flash(:error, "Workflow could not be saved")
      end
      |> push_patches_applied(initial_params)

    {:noreply, socket}
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

    {:reply, %{patches: patches}, socket}
  end

  def handle_event("copied_to_clipboard", _, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Copied webhook URL to clipboard")}
  end

  defp webhook_url(changeset) do
    if Ecto.Changeset.get_field(changeset, :type) == :webhook do
      if id = Ecto.Changeset.get_field(changeset, :id) do
        Routes.webhooks_url(LightningWeb.Endpoint, :create, [id])
      end
    end
  end

  def send_form_changed(params) do
    send(self(), {"form_changed", params})
  end

  @impl true
  def handle_info({"form_changed", %{"workflow" => params}}, socket) do
    initial_params = socket.assigns.workflow_params

    next_params =
      WorkflowParams.apply_form_params(socket.assigns.workflow_params, params)

    {:noreply,
     socket
     |> apply_params(next_params)
     |> push_patches_applied(initial_params)}
  end

  defp assign_workflow(socket, workflow) do
    changeset = Workflow.changeset(workflow, %{})
    IO.inspect(changeset)

    socket
    |> assign(
      workflow: workflow,
      changeset: changeset,
      workflow_params: WorkflowParams.to_map(changeset)
    )
  end

  defp maybe_assign_workflow(socket, workflow_id) do
    case socket.assigns do
      %{workflow: %{id: ^workflow_id}} ->
        socket

      # "new" -> ?

      _ ->
        workflow =
          Workflows.get_workflow(workflow_id)
          |> Lightning.Repo.preload([:jobs, :triggers, :edges])

        socket
        |> assign_workflow(workflow)
    end
  end

  defp apply_params(socket, params) do
    # Build a new changeset from the new params
    changeset = socket.assigns.workflow |> Workflow.changeset(params)

    socket |> assign_changeset(changeset)
  end

  defp assign_changeset(socket, changeset) do
    # Prepare a new set of workflow params from the changeset
    workflow_params = changeset |> WorkflowParams.to_map()

    socket |> assign(changeset: changeset, workflow_params: workflow_params)
  end

  defp push_patches_applied(socket, initial_params) do
    next_params = socket.assigns.workflow_params

    patches = WorkflowParams.to_patches(initial_params, next_params)

    socket
    |> push_event("patches-applied", %{patches: patches})
  end

  defp unselect_all(socket) do
    socket
    |> assign(selected_job: nil, selected_trigger: nil, selected_edge: nil)
  end

  defp select_node(socket, [{type, value}]) do
    case type do
      :job ->
        socket
        |> assign(selected_job: value, selected_trigger: nil, selected_edge: nil)

      :trigger ->
        socket
        |> assign(selected_job: nil, selected_trigger: value, selected_edge: nil)

      :edge ->
        socket
        |> assign(selected_job: nil, selected_trigger: nil, selected_edge: value)
    end
  end
end
