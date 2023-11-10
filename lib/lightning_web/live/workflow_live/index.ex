defmodule LightningWeb.WorkflowLive.Index do
  @moduledoc false
  use LightningWeb, :live_view

  import Ecto.Changeset
  alias Lightning.Workflows
  @form_fields %{name: nil, project_id: nil}
  @types %{name: :string, project_id: :string}

  on_mount {LightningWeb.Hooks, :project_scope}

  alias Lightning.Workflows
  alias Lightning.Policies.{Permissions, ProjectUsers}
  import LightningWeb.WorkflowLive.Components

  attr :can_create_workflow, :boolean
  attr :can_delete_workflow, :boolean
  attr :workflows, :list
  attr :project, Lightning.Projects.Project

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:title><%= @page_title %></:title>
        </LayoutComponents.header>
      </:header>
      <div class="relative h-full flex">
        <LayoutComponents.centered>
          <.workflow_list
            can_create_workflow={@can_create_workflow}
            can_delete_workflow={@can_delete_workflow}
            workflows={@workflows}
            project={@project}
          />
          <.create_workflow_modal form={@form} isButtonDisabled={@isButtonDisabled} />
        </LayoutComponents.centered>
      </div>
    </LayoutComponents.page_content>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    can_create_workflow =
      ProjectUsers
      |> Permissions.can?(
        :create_workflow,
        socket.assigns.current_user,
        socket.assigns.project
      )

    can_delete_workflow =
      ProjectUsers
      |> Permissions.can?(
        :delete_workflow,
        socket.assigns.current_user,
        socket.assigns.project
      )

    {:ok,
     socket
     |> workflow_modal_form()
     |> assign(
       can_delete_workflow: can_delete_workflow,
       can_create_workflow: can_create_workflow
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(
      active_menu_item: :overview,
      page_title: "Workflows",
      workflows: Workflows.get_workflows_for(socket.assigns.project)
    )
  end

  @impl true
  def handle_event(
        "create_work_flow",
        %{"workflow_name" => workflow_name},
        socket
      ) do
    changeset = validate_workflow(workflow_name, socket)

    if changeset.valid? do
      navigate_to_new_workflow(socket, workflow_name)
    else
      {:noreply, update_form(socket, changeset)}
    end
  end

  @impl true
  def handle_event("delete_workflow", %{"id" => id}, socket) do
    if socket.assigns.can_delete_workflow do
      Workflows.get_workflow!(id)
      |> Workflows.mark_for_deletion()
      |> case do
        {:ok, _} ->
          {
            :noreply,
            socket
            |> assign(
              workflows: Workflows.get_workflows_for(socket.assigns.project)
            )
            |> put_flash(:info, "Workflow successfully deleted.")
          }

        {:error, _changeset} ->
          {:noreply, socket |> put_flash(:error, "Can't delete workflow")}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action.")}
    end
  end

  @impl true
  def handle_event("validate", %{"workflow_name" => workflow_name}, socket) do
    IO.inspect(workflow_name, label: "Name workflow")
    changeset = validate_workflow(workflow_name, socket)

    socket =
      socket
      |> assign(:isButtonDisabled, not changeset.valid?)

    {:noreply, assign(socket, form: to_form(changeset, as: :input_form))}
  end

  defp validate_workflow(workflow_name, socket) do
    validate_workflow_name(@form_fields, %{
      name: workflow_name,
      project_id: socket.assigns.project.id
    })
    |> Map.put(:action, :validate)
  end

  defp navigate_to_new_workflow(socket, workflow_name) do
    {:noreply,
     push_navigate(socket,
       to:
         ~p"/projects/#{socket.assigns.project.id}/w/new?#{%{name: workflow_name}}"
     )}
  end

  defp update_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :input_form))
  end

  defp changeset(workflow, attrs) do
    {workflow, @types}
    |> cast(attrs, Map.keys(@types))
    |> validate_required([:name])
    |> validate_unique_name?()
  end

  defp validate_unique_name?(changeset) do
    workflow_name = get_field(changeset, :name)
    project_id = get_field(changeset, :project_id)

    if workflow_name && project_id do
      case Workflows.workflow_exists?(project_id, workflow_name) do
        true ->
          add_error(changeset, :name, "Workflow name already been used")

        false ->
          changeset
      end
    else
      changeset
    end
  end

  defp validate_workflow_name(workflow, attrs \\ %{}) do
    changeset(workflow, attrs)
  end

  defp workflow_modal_form(socket) do
    changeset = validate_workflow_name(@form_fields)

    socket
    |> assign(:form, to_form(changeset, as: :input_form))
    |> assign(:isButtonDisabled, not changeset.valid?)
  end
end
