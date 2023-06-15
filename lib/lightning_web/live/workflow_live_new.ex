defmodule LightningWeb.WorkflowNewLive do
  @moduledoc false
  use LightningWeb, :live_view

  alias Lightning.Policies.ProjectUsers
  alias Lightning.Policies.Permissions
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
          data-edit-edge-url={~p"/projects/#{@project.id}/w-new/new/e/:edge_id"}
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
        <div
          :if={@selected_edge}
          class="grow-0 w-1/2 relative min-w-[300px] max-w-[90%]"
          lv-keep-style
        >
          <.resize_component id={"resizer-#{@workflow.id}"} />
          <div class="absolute inset-y-0 left-2 right-0 z-10 resize-x ">
            <div class="w-auto h-full" id={"edge-pane-#{@workflow.id}"}>
              <.form
                :let={f}
                for={@changeset}
                phx-submit="save"
                phx-change="validate"
                class="h-full"
              >
                <%= for edge_form <- single_inputs_for(f, :edges, @selected_edge |> Ecto.Changeset.get_field(:id)) do %>
                  <!-- Show only the currently selected one -->
                  <.edge_form
                    :if={
                      Ecto.Changeset.get_field(edge_form.source, :id) ==
                        Ecto.Changeset.get_field(@selected_edge, :id)
                    }
                    form={edge_form}
                    disabled={!@can_edit_job}
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

  defp single_inputs_for(form, field, id) do
    form
    |> inputs_for(field)
    |> Enum.filter(&(Ecto.Changeset.get_field(&1.source, :id) == id))
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
       selected_edge: nil,
       page_title: "",
       active_menu_item: :projects,
       can_edit_job: can_edit_job
     )
     |> maybe_assign_workflow()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp maybe_assign_workflow(socket) do
    if socket.assigns[:workflow] do
      socket
    else
      workflow = %Workflow{}
      job_1_id = Ecto.UUID.generate()
      job_2_id = Ecto.UUID.generate()
      trigger_1_id = Ecto.UUID.generate()

      params = %{
        "name" => nil,
        "project_id" => socket.assigns.project.id,
        "jobs" => [
          %{"id" => job_1_id, "name" => "job-1"},
          %{"id" => job_2_id, "name" => "job-2"}
        ],
        "triggers" => [
          %{"id" => trigger_1_id, "type" => "webhook"}
        ],
        "edges" => [
          %{
            "id" => Ecto.UUID.generate(),
            "source_trigger_id" => trigger_1_id,
            "condition" => "true",
            "target_job_id" => job_1_id
          },
          %{
            "id" => Ecto.UUID.generate(),
            "source_job_id" => job_1_id,
            "condition" => ":on_success",
            "target_job_id" => job_2_id
          }
        ]
      }

      socket |> assign(workflow: workflow) |> apply_params(params)
    end
  end

  def apply_action(socket, :new, _params) do
    assign(socket,
      page_title: "New Workflow"
    )
    |> maybe_assign_workflow()
    |> unselect_all()
  end

  @impl true
  def handle_event("get-initial-state", _params, socket) do
    {:reply, socket.assigns.workflow_params, socket}
  end

  def handle_event("hash-changed", %{"hash" => hash}, socket) do
    id = Regex.run(~r/^#(.*)$/, hash) |> List.wrap() |> Enum.at(1)

    # find the changeset for the selected item
    # it could be an edge, a job or a trigger
    [:jobs, :triggers, :edges]
    |> Enum.reduce_while(nil, fn field, _ ->
      Ecto.Changeset.get_change(socket.assigns.changeset, field, [])
      |> Enum.find(fn changeset ->
        Ecto.Changeset.get_field(changeset, :id) == id
      end)
      |> case do
        nil ->
          {:cont, nil}

        changeset ->
          {:halt, [field, changeset]}
      end
    end)
    |> case do
      nil ->
        {:noreply, socket}

      [type, selected] ->
        {:noreply, socket |> select_node({type, selected})}
    end
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
    initial_params = socket.assigns.workflow_params

    next_params =
      WorkflowParams.apply_form_params(socket.assigns.workflow_params, params)

    {:noreply,
     socket
     |> apply_params(next_params)
     |> push_patches_applied(initial_params)}
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

  defp apply_params(socket, params) do
    # Build a new changeset from the new params
    changeset = socket.assigns.workflow |> Workflow.changeset(params)

    # Prepare a new set of workflow params from the changeset
    workflow_params = changeset |> WorkflowParams.to_map()

    socket
    |> assign(changeset: changeset, workflow_params: workflow_params)
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

  defp select_node(socket, {type, value}) do
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
  end
end
