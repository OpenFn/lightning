defmodule LightningWeb.WorkflowLive.Edit do
  @moduledoc false
  use LightningWeb, :live_view

  alias Lightning.Policies.ProjectUsers
  alias Lightning.Policies.Permissions
  alias Lightning.Projects
  alias Lightning.Workflows
  alias Lightning.Workflows.Workflow
  alias LightningWeb.Components.Form
  alias LightningWeb.WorkflowNewLive.WorkflowParams

  import LightningWeb.WorkflowLive.Components

  on_mount({LightningWeb.Hooks, :project_scope})

  attr(:changeset, :map, required: true)
  attr(:project_user, :map, required: true)

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
            form="workflow-form"
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
            <.form
              :let={f}
              id="workflow-form"
              for={@changeset}
              phx-submit="save"
              phx-change="validate"
              class="h-full"
            >
              <.panel id={"job-pane-#{@workflow.id}"}>
                <:header>
                  <div class="grow">
                    <%= f
                    |> input_value(:name)
                    |> then(fn
                      "" -> "Untitled Job"
                      name -> name
                    end) %>
                  </div>
                  <div class="flex-none">
                    <.link
                      patch={~p"/projects/#{@project.id}/w/#{@workflow.id || "new"}"}
                      class="justify-center hover:text-gray-500"
                    >
                      <Heroicons.x_mark solid class="h-4 w-4 inline-block" />
                    </.link>
                  </div>
                </:header>

                <%= for job_form <- single_inputs_for(f, :jobs, @selected_job.id) do %>
                  <!-- Show only the currently selected one -->
                  <.job_form
                    on_change={&send_form_changed/1}
                    form={job_form}
                    project_user={@project_user}
                  />
                <% end %>
                <:footer>
                  <button
                    type="button"
                    class="px-4 py-1.5 h-10 inline-flex items-center gap-x-1.5
                    rounded-md bg-indigo-600 text-sm font-semibold text-white
                    shadow-sm hover:bg-indigo-500
                    focus-visible:outline focus-visible:outline-2
                    focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
                    phx-click="set_expanded_job_modal"
                    phx-value-show="true"
                  >
                    <Heroicons.pencil_square class="w-4 h-4 -ml-0.5" /> Edit
                  </button>
                </:footer>
                <LightningWeb.Components.Modal.modal
                  :let={close_modal}
                  :if={@show_expanded_job_modal}
                  id="expanded-job-modal"
                  show={@show_expanded_job_modal}
                >
                  <div class="bg-white overscroll-none inset-4 resize-x">
                    <div class="z-50 flex flex-col h-full">
                      <div class="w-full">
                        <div class="p-5 flex flex-row h-1/6">
                          <div><%= @selected_job.adaptor %></div>
                          <div class="grow">
                            <%= if @selected_job.credential != nil do %>
                              <%= @selected_job.credential.name %>
                            <% else %>
                              <%= "No Credentials" %>
                            <% end %>
                          </div>
                          <div class="grow">
                            <%= @selected_job.name %>

                          </div>
                        <div class="flex-none">
                            <button
                              type="button"
                              phx-click={close_modal}
                              class="text-gray-400 hover:text-gray-500"
                            >
                              <div class="sr-only">Close</div>
                              <Heroicons.x_mark class="w-6 h-6" />
                            </button>
                        </div>
                        </div>
                      </div>
                      <div class="grow overflow-y-auto">
                        <div class="grid grid-cols-3 divide-x">
                          <div>Input</div>
                          <div>Editor</div>
                          <div>Output</div>
                        </div>
                      </div>
                      <div class="flex-none h-1/6">
                        <span> Reruns  Buttons </span>
                      </div>
                    </div>
                  </div>
                </LightningWeb.Components.Modal.modal>
              </.panel>
            </.form>
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
                id="workflow-form"
                for={@changeset}
                phx-submit="save"
                phx-change="validate"
                class="h-full"
              >
                <%= for trigger_form <- single_inputs_for(f, :triggers, @selected_trigger.id) do %>
                  <!-- Show only the currently selected one -->
                  <.trigger_form
                    form={trigger_form}
                    on_change={&send_form_changed/1}
                    requires_cron_job={
                      Ecto.Changeset.get_field(trigger_form.source, :type) == :cron
                    }
                    disabled={!@can_edit_job}
                    webhook_url={webhook_url(trigger_form.source)}
                    cancel_url={
                      ~p"/projects/#{@project.id}/w/#{@workflow.id || "new"}"
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
                id="workflow-form"
                for={@changeset}
                phx-submit="save"
                phx-change="validate"
                class="h-full"
              >
                <%= for edge_form <- single_inputs_for(f, :edges, @selected_edge.id) do %>
                  <!-- Show only the currently selected one -->
                  <.edge_form
                    form={edge_form}
                    disabled={!@can_edit_job}
                    cancel_url={
                      ~p"/projects/#{@project.id}/w/#{@workflow.id || "new"}"
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

    project_user = Projects.get_project_user(project, socket.assigns.current_user)

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
       active_menu_item: :projects,
       can_edit_job: can_edit_job,
       expanded_job: nil,
       page_title: "",
       project: project,
       project_user: project_user,
       show_expanded_job_modal: false,
       selection_mode: nil,
       selected_edge: nil,
       selected_job: nil,
       selected_trigger: nil,
       show_edit_modal: false
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
    |> assign_workflow(%Workflow{project_id: socket.assigns.project.id})
    |> unselect_all()
  end

  def apply_action(socket, :edit, %{"id" => workflow_id}) do
    # TODO we shouldn't be calling Repo from here
    workflow =
      Workflows.get_workflow(workflow_id)
      |> Lightning.Repo.preload([
        :triggers,
        :edges,
        jobs: [:credential]
      ])

    assign(socket,
      page_title: "New Workflow"
    )
    |> assign_workflow(workflow)
    |> unselect_all()
  end

  @impl true
  def handle_event("get-initial-state", _params, socket) do
    {:reply, socket.assigns.workflow_params, socket}
  end

  def handle_event("set_expanded_job_modal", %{"show" => show}, socket)
      when show in ["true", "false"] do
    {:noreply,
     socket |> assign(show_expanded_job_modal: show |> String.to_existing_atom())}
  end

  def handle_event("modal_closed", _, socket) do
    {:noreply, socket |> assign(show_expanded_job_modal: false)}
  end

  def handle_event("hash-changed", %{"hash" => hash}, socket) do
    with {"#", query} <- String.split_at(hash, 1),
         %{"id" => id, "mode" => mode} <-
           URI.decode_query(query) |> Enum.into(%{"mode" => nil}),
         [type, selected] <- find_item_in_changeset(socket.assigns.changeset, id) do
      {:noreply,
       socket
       |> select_node({type, selected}, mode)}
    else
      _ -> {:noreply, socket |> unselect_all()}
    end
  end

  def handle_event("validate", %{"workflow" => params}, socket) do
    initial_params = socket.assigns.workflow_params

    next_params = WorkflowParams.apply_form_params(socket.assigns.workflow_params, params)

    {:noreply,
     socket
     |> apply_params(next_params)
     |> push_patches_applied(initial_params)}
  end

  def handle_event("save", %{"workflow" => params} = all, socket) do
    IO.inspect(all)
    # update the changeset
    # then do the 'normal' insert or update

    initial_params = socket.assigns.workflow_params

    next_params = WorkflowParams.apply_form_params(socket.assigns.workflow_params, params)

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
          |> put_flash(:error, "Workflow could not be saved")
      end
      |> push_patches_applied(initial_params)

    {:noreply, socket}
  end

  def handle_event("push-change", %{"patches" => patches}, socket) do
    # Apply the incoming patches to the current workflow params producing a new
    # set of params.
    {:ok, params} = WorkflowParams.apply_patches(socket.assigns.workflow_params, patches)

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

  @impl true
  def handle_info({"form_changed", %{"workflow" => params}}, socket) do
    initial_params = socket.assigns.workflow_params

    next_params = WorkflowParams.apply_form_params(socket.assigns.workflow_params, params)

    {:noreply,
     socket
     |> apply_params(next_params)
     |> push_patches_applied(initial_params)}
  end

  def handle_info({"expanded_modal_closed", _target}, socket) do
    {:noreply, socket |> assign(show_expanded_job_modal: false)}
  end

  defp webhook_url(changeset) do
    if Ecto.Changeset.get_field(changeset, :type) == :webhook do
      if id = Ecto.Changeset.get_field(changeset, :id) do
        Routes.webhooks_url(LightningWeb.Endpoint, :create, [id])
      end
    end
  end

  defp send_form_changed(params) do
    send(self(), {"form_changed", params})
  end

  defp assign_workflow(socket, workflow) do
    changeset = Workflow.changeset(workflow, %{})

    socket
    |> assign(
      workflow: workflow,
      changeset: changeset,
      workflow_params: WorkflowParams.to_map(changeset)
    )
  end

  defp apply_params(socket, params) do
    # Build a new changeset from the new params
    changeset =
      socket.assigns.workflow
      |> Workflow.changeset(
        params
        |> Map.put("project_id", socket.assigns.project.id)
      )

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

  # find the changeset for the selected item
  # it could be an edge, a job or a trigger
  defp find_item_in_changeset(changeset, id) do
    [:jobs, :triggers, :edges]
    |> Enum.reduce_while(nil, fn field, _ ->
      Ecto.Changeset.get_field(changeset, field, [])
      |> Enum.find(&(&1.id == id))
      |> case do
        nil ->
          {:cont, nil}

        changeset ->
          {:halt, [field, changeset]}
      end
    end)
  end
end
