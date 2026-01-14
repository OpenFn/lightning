defmodule LightningWeb.WorkflowLive.NewWorkflowComponent do
  @moduledoc """
  Comprehensive LiveView component for creating new workflows through multiple methods.

  This component provides a unified interface for workflow creation, supporting three
  distinct creation methods while maintaining a consistent user experience and
  validation pipeline. It serves as the primary entry point for all workflow
  creation workflows within Lightning.
  """
  use LightningWeb, :live_component

  alias Lightning.Projects
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkflowTemplates
  alias LightningWeb.API.ProvisioningJSON
  alias LightningWeb.Live.AiAssistant.ModeRegistry
  alias Phoenix.LiveView.JS

  require Logger

  @impl true
  def mount(socket) do
    base_templates = base_templates()
    users_templates = WorkflowTemplates.list_templates()

    {:ok,
     socket
     |> assign(base_url: nil)
     |> assign(search_term: "")
     |> assign(chat_session_id: nil)
     |> assign(selected_template: nil)
     |> assign(workflow_code: nil)
     |> assign(session_or_message: nil)
     |> assign(validation_failed: true)
     |> assign(selected_method: "template")
     |> assign(base_templates: base_templates)
     |> assign(users_templates: users_templates)
     |> assign(filtered_templates: users_templates)
     |> assign(all_templates: base_templates ++ users_templates)}
  end

  @impl true
  def update(
        %{
          action: :workflow_code_generated,
          workflow_code: code,
          session_or_message: session_or_message
        },
        socket
      ) do
    {:ok,
     socket
     |> assign(session_or_message: session_or_message)
     |> assign(workflow_code: code)
     |> then(fn s ->
       if code,
         do: push_event(s, "template_selected", %{template: code}),
         else: s
     end)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:changeset, fn %{workflow: workflow} ->
       Workflow.changeset(workflow, %{})
     end)}
  end

  @impl true
  def handle_event("choose-another-method", %{"method" => method}, socket) do
    socket =
      assign(socket, changeset: Workflow.changeset(socket.assigns.workflow, %{}))

    case method do
      "ai" ->
        handle_ai_method_selection(socket)

      _ ->
        handle_regular_method_selection(socket, method)
    end
  end

  def handle_event("search-templates", %{"search" => search_term}, socket) do
    filtered_templates =
      filter_templates(socket.assigns.users_templates, search_term)

    {:noreply,
     socket
     |> assign(search_term: search_term)
     |> assign(filtered_templates: filtered_templates)}
  end

  def handle_event("select-template", %{"template_id" => template_id}, socket) do
    template = Enum.find(socket.assigns.all_templates, &(&1.id == template_id))

    notify_parent(:canvas_state_changed, %{
      show_canvas_placeholder: false,
      show_template_tooltip: template
    })

    {:noreply,
     socket
     |> assign(selected_template: template)
     |> push_event("template_selected", %{template: template.code})}
  end

  def handle_event(
        event_name,
        %{"workflow" => params},
        %{assigns: %{project: project, selected_template: template}} = socket
      )
      when event_name in ["workflow-parsed", "template-parsed"] do
    params = ensure_unique_name(params, project)
    changeset = Workflow.changeset(socket.assigns.workflow, params)

    if changeset.valid? do
      template_for_tooltip = get_template_for_tooltip(event_name, template)

      notify_parent(:canvas_state_changed, %{
        show_canvas_placeholder: false,
        show_template_tooltip: template_for_tooltip
      })

      notify_parent(:workflow_params_changed, %{"workflow" => params})

      {:noreply,
       socket
       |> assign(changeset: changeset)
       |> assign(validation_failed: false)
       |> push_event("workflow-validated", %{})
       |> push_event("state-applied", %{"state" => params})
       |> push_event("force-fit", %{})}
    else
      notify_parent(:canvas_state_changed, %{
        show_canvas_placeholder: true,
        show_template_tooltip: nil
      })

      {:noreply,
       socket
       |> assign(changeset: changeset)
       |> assign(validation_failed: true)
       |> assign_error_changeset(changeset, event_name)
       |> push_event(
         "workflow-validation-errors",
         ProvisioningJSON.error(%{changeset: changeset})
       )}
    end
  end

  def handle_event("template-parse-error", %{"error" => error}, socket) do
    notify_parent(:canvas_state_changed, %{
      show_canvas_placeholder: true,
      show_template_tooltip: nil
    })

    {:noreply, send_error(socket, error)}
  end

  def handle_event(
        "workflow-parsing-failed",
        %{"error" => error_message},
        socket
      ) do
    notify_parent(:canvas_state_changed, %{
      show_canvas_placeholder: true,
      show_template_tooltip: nil
    })

    {:noreply,
     socket
     |> assign(validation_failed: true)
     |> push_event("show-parsing-error", %{error: error_message})}
  end

  def handle_event(_event, _params, socket) do
    {:noreply, socket}
  end

  defp send_error(socket, error) do
    Logger.error("Workflow code parse failed: #{inspect(error)}")

    send_update(
      LightningWeb.AiAssistant.Component,
      id: socket.assigns.ai_assistant_component_id,
      action: :code_error,
      error: error,
      session_or_message: socket.assigns.session_or_message
    )

    socket
  end

  defp ensure_unique_name(params, project) do
    workflow_name =
      params["name"]
      |> to_string()
      |> String.trim()
      |> case do
        "" -> "Untitled workflow"
        name -> name
      end

    existing_workflows = Projects.list_workflows(project)
    unique_name = generate_unique_name(workflow_name, existing_workflows)

    Map.put(params, "name", unique_name)
  end

  defp get_template_for_tooltip("template-parsed", template), do: template
  defp get_template_for_tooltip("workflow-parsed", _template), do: nil

  defp assign_error_changeset(socket, changeset, "workflow-parsed"),
    do: assign(socket, changeset: changeset)

  defp assign_error_changeset(socket, _changeset, "template-parsed"), do: socket

  defp generate_unique_name(base_name, existing_workflows) do
    existing_names = MapSet.new(existing_workflows, & &1.name)

    if MapSet.member?(existing_names, base_name) do
      find_available_name(base_name, existing_names)
    else
      base_name
    end
  end

  defp find_available_name(base_name, existing_names) do
    1
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(&"#{base_name} #{&1}")
    |> Enum.find(&name_available?(&1, existing_names))
  end

  defp name_available?(name, existing_names) do
    not MapSet.member?(existing_names, name)
  end

  defp filter_templates(templates, search_term)
       when is_binary(search_term) and search_term != "" do
    search_term = String.downcase(search_term)

    matches_search_term = fn template ->
      name_match =
        template.name &&
          String.contains?(String.downcase(template.name), search_term)

      description_match =
        template.description &&
          String.contains?(String.downcase(template.description), search_term)

      tags_match =
        template.tags &&
          Enum.any?(
            template.tags,
            &String.contains?(String.downcase(&1), search_term)
          )

      name_match || description_match || tags_match
    end

    Enum.filter(templates, matches_search_term)
  end

  defp filter_templates(templates, _), do: templates

  defp notify_parent(action, payload) do
    send(self(), {:ai_assistant, action, payload})
  end

  defp handle_ai_method_selection(socket) do
    search_term = socket.assigns.search_term

    if search_term && String.trim(search_term) != "" do
      case create_ai_session_for_input(socket.assigns, search_term) do
        {:ok, session_id} ->
          notify_parent(:canvas_state_changed, %{
            show_canvas_placeholder: true,
            show_template_tooltip: nil
          })

          {:noreply,
           socket
           |> assign(selected_method: "ai")
           |> assign(selected_template: nil)
           |> assign(chat_session_id: session_id)
           |> assign(search_term: nil)
           |> push_patch(
             to:
               "/projects/#{socket.assigns.project.id}/w/new/legacy?method=ai&w-chat=#{session_id}"
           )}

        {:error, reason} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to create AI session: #{reason}")
           |> handle_regular_method_selection("ai")}
      end
    else
      handle_regular_method_selection(socket, "ai")
    end
  end

  defp handle_regular_method_selection(socket, method) do
    notify_parent(:canvas_state_changed, %{
      show_canvas_placeholder: true,
      show_template_tooltip: nil
    })

    {:noreply,
     socket
     |> assign(selected_method: method)
     |> assign(selected_template: nil)
     |> assign(chat_session_id: nil)
     |> push_patch(
       to: "/projects/#{socket.assigns.project.id}/w/new/legacy?method=#{method}"
     )}
  end

  defp create_ai_session_for_input(assigns, input_value) do
    handler = ModeRegistry.get_handler(:workflow)

    session_assigns = %{
      project: assigns.project,
      user: assigns.user
    }

    case handler.create_session(session_assigns, input_value) do
      {:ok, session} -> {:ok, session.id}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        filtered_templates:
          Enum.sort_by(
            assigns.filtered_templates,
            & &1.name
          )
      )

    ~H"""
    <div id={@id} class="w-1/3">
      <div class="bg-white h-full flex flex-col border-r-1">
        <div class="flex-grow overflow-hidden flex flex-col">
          <div
            :if={@selected_method != "ai"}
            class="px-2 py-2 sm:px-4 sm:py-2 flex-grow"
          >
            <.create_workflow_from_template
              :if={@selected_method == "template"}
              myself={@myself}
              search_term={@search_term}
              filtered_templates={@filtered_templates}
              base_templates={@base_templates}
              selected_template={@selected_template}
              project={@project}
            />
            <.create_workflow_via_import
              :if={@selected_method == "import"}
              myself={@myself}
              changeset={@changeset}
            />
          </div>
          <.create_workflow_via_ai
            :if={@selected_method == "ai"}
            parent_id={@id}
            project={@project}
            user={@user}
            can_edit={@can_edit}
            chat_session_id={@chat_session_id}
            query_params={@query_params}
            workflow_code={@workflow_code}
            base_url={@base_url}
            search_term={@search_term}
            ai_assistant_component_id={@ai_assistant_component_id}
          />
        </div>
        <div class="px-4 py-4 sm:p-3 flex flex-row justify-end gap-2 h-max border-t">
          <.button
            :if={@selected_method == "template"}
            id="import-workflow-btn"
            type="button"
            theme="secondary"
            class="inline-flex gap-x-1 px-4"
            phx-click="choose-another-method"
            phx-value-method="import"
            phx-target={@myself}
          >
            <.icon name="hero-document-arrow-up" class="size-5" /> Import
          </.button>
          <.button
            :if={@selected_method != "template"}
            id="move-back-to-templates-btn"
            type="button"
            theme="secondary"
            class="inline-flex gap-x-1 px-4"
            phx-click="choose-another-method"
            phx-value-method="template"
            phx-target={@myself}
          >
            Back
          </.button>
          <.button
            id="create_workflow_btn"
            type="button"
            theme="primary"
            class="inline-flex gap-x-1 px-4"
            {if !create_disabled?(assigns), do: ["phx-click": JS.push("save")], else: []}
            phx-disconnected={JS.set_attribute({"disabled", ""})}
            phx-connected={
              !create_disabled?(assigns) && JS.remove_attribute("disabled")
            }
            disabled={create_disabled?(assigns)}
          >
            Create
          </.button>
        </div>
      </div>
    </div>
    """
  end

  attr :selected_template, :map, required: true
  attr :myself, :any, required: true
  attr :search_term, :string, required: true
  attr :project, :any, required: true

  defp ai_template_card(assigns) do
    ~H"""
    <button
      type="button"
      id="template-label-ai-dynamic-template"
      phx-click="choose-another-method"
      phx-value-method="ai"
      phx-target={@myself}
      class="relative flex flex-col cursor-pointer rounded-md border border-indigo-300/40 p-4 transition-all duration-300 no-underline w-full text-left ai-bg-gradient hover:\digo-300/80 group h-24"
      style="appearance: none;"
    >
      <span class="flex-1 overflow-hidden flex flex-col relative z-10">
        <span class="font-semibold text-white line-clamp-1 flex items-center">
          Build with AI ✨
        </span>
        <span class="text-sm text-indigo-100/90 line-clamp-2">
          {@search_term}
        </span>
      </span>
    </button>
    """
  end

  defp create_workflow_from_template(assigns) do
    ~H"""
    <div
      id="create-workflow-from-template"
      phx-hook="TemplateToWorkflow"
      class="flex flex-col p-1 gap-3 h-full overflow-hidden"
    >
      <div class="mt-2 mb-2">
        <.form
          id="search-templates-form"
          phx-change="search-templates"
          phx-target={@myself}
          phx-debounce="300"
          for={to_form(%{"search" => @search_term})}
        >
          <div class="relative rounded-md">
            <.input_element
              type="text"
              name="search"
              placeholder="Describe your workflow"
              class="block w-full rounded-md border-0 py-2 pl-10 pr-4 text-gray-900 ring-1 ring-gray-300 focus:ring-2 focus:ring-indigo-600 sm:text-sm"
              value={@search_term}
            />
            <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
              <.icon name="hero-magnifying-glass" class="size-5 text-gray-400" />
            </div>
          </div>
        </.form>
      </div>

      <div
        :if={length(@filtered_templates) == 0 && @search_term != ""}
        class="text-center italic text-gray-400 text-sm hidden opacity-0"
        phx-mounted={fade_in()}
        phx-remove={fade_out()}
      >
        We don't have any templates matching this description. Want to try a base template or drafting this workflow with AI?
      </div>

      <.form
        id="choose-workflow-template-form"
        phx-change="select-template"
        phx-target={@myself}
        for={to_form(%{})}
        class="flex-grow overflow-hidden flex flex-col"
      >
        <fieldset class="overflow-y-auto flex-grow min-h-0 h-0">
          <div class="grid lg:grid-cols-1 xl:grid-cols-2 gap-2 pb-4">
            <label
              :for={template <- @base_templates}
              id={"template-label-#{template.id}"}
              data-selected={"#{@selected_template && template.id == @selected_template.id}"}
              for={"template-input-#{template.id}"}
              class={[
                "relative flex flex-col cursor-pointer rounded-md border bg-white p-4 hover:bg-gray-50 transition-all h-24",
                if(@selected_template && template.id == @selected_template.id,
                  do: "border-indigo-600 border-1",
                  else: "border-gray-300"
                )
              ]}
            >
              <input
                id={"template-input-#{template.id}"}
                type="radio"
                name="template_id"
                value={template.id}
                class="sr-only"
              />
              <span class="flex-1 overflow-hidden flex flex-col">
                <span class="font-medium text-gray-900 line-clamp-1">
                  {template.name}
                </span>
                <span class="text-sm text-gray-500 line-clamp-2">
                  {template.description}
                </span>
              </span>
            </label>
            <.ai_template_card
              project={@project}
              selected_template={@selected_template}
              search_term={
                if @search_term == "",
                  do: "Build your workflow using the AI assistant",
                  else: @search_term
              }
              myself={@myself}
            />
            <label
              :for={template <- @filtered_templates}
              id={"template-label-#{template.id}"}
              data-selected={"#{@selected_template && template.id == @selected_template.id}"}
              for={"template-input-#{template.id}"}
              class={[
                "relative flex flex-col cursor-pointer rounded-md border bg-white p-4 hover:bg-gray-50 transition-all h-24",
                if(@selected_template && template.id == @selected_template.id,
                  do: "border-indigo-600 border-1",
                  else: "border-gray-300"
                )
              ]}
            >
              <input
                id={"template-input-#{template.id}"}
                type="radio"
                name="template_id"
                value={template.id}
                class="sr-only"
              />
              <span class="flex-1 overflow-hidden flex flex-col">
                <span class="font-medium text-gray-900 line-clamp-1">
                  {template.name}
                </span>
                <span class="text-sm text-gray-500 line-clamp-2">
                  {template.description}
                </span>
              </span>
            </label>
          </div>
        </fieldset>
      </.form>
    </div>
    """
  end

  attr :changeset, Ecto.Changeset, required: true
  attr :myself, :any, required: true

  defp create_workflow_via_import(assigns) do
    ~H"""
    <div
      id="workflow-importer"
      phx-hook="YAMLToWorkflow"
      data-file-input-el="workflow-file"
      data-viewer-el="workflow-code-viewer"
      data-error-el="workflow-errors"
      class="flex flex-col gap-3 h-full relative"
    >
      <div
        id="workflow-errors"
        class="hidden absolute top-0 left-0 right-0 z-10 bg-danger-100/80 border border-danger-200 text-danger-800 px-4 py-3 rounded-lg flex items-start gap-3 shadow-sm"
      >
      </div>
      <div
        id="workflow-dropzone"
        phx-hook="FileDropzone"
        class="mt-2 flex justify-center rounded-lg border border-dashed border-gray-900/25 px-6 py-10 transition-colors duration-200 ease-in-out"
        data-target="#workflow-file"
      >
        <div class="text-center">
          <Heroicons.cloud_arrow_up class="mx-auto size-10 text-gray-300" />
          <div class="mt-4 flex text-sm/6 text-gray-600">
            <label
              for="workflow-file"
              class="relative cursor-pointer rounded-md font-semibold text-indigo-600 focus-within:outline-none focus-within:ring-offset-2 hover:text-indigo-500"
            >
              <span>Upload a file</span>
              <input
                id="workflow-file"
                name="workflow-file"
                type="file"
                class="sr-only"
                accept=".yml,.yaml"
                phx-update="ignore"
              />
            </label>
            <p class="pl-1">or drag and drop</p>
          </div>
          <p class="text-xs/5 text-gray-600">YML or YAML, up to 8MB</p>
        </div>
      </div>
      <div class="relative">
        <div class="absolute inset-0 flex items-center" aria-hidden="true">
          <div class="w-full border-t border-gray-300"></div>
        </div>
        <div class="relative flex justify-center">
          <span class="bg-white px-2 text-sm text-gray-500">OR</span>
        </div>
      </div>
      <div class="flex-grow flex flex-col">
        <.textarea_element
          id="workflow-code-viewer"
          phx-update="ignore"
          name="workflow-code"
          value=""
          class="font-mono proportional-nums text-slate-200 bg-slate-700 resize-none text-nowrap overflow-x-auto flex-grow"
          placeholder="Paste your YAML content here"
        />
      </div>
    </div>
    """
  end

  @spec build_ai_callbacks(String.t()) :: map()
  defp build_ai_callbacks(parent_id) do
    %{
      on_session_close: fn ->
        notify_parent(:canvas_state_changed, %{
          show_canvas_placeholder: true,
          show_template_tooltip: nil
        })

        send_workflow_update(parent_id, nil, nil)
      end,
      on_session_open: &send_workflow_update(parent_id, &1, &2),
      on_message_selected: &send_workflow_update(parent_id, &1, &2),
      on_message_received: &send_workflow_update(parent_id, &1, &2)
    }
  end

  @spec send_workflow_update(String.t(), String.t() | nil, any()) :: :ok
  defp send_workflow_update(parent_id, code, session_or_message) do
    send_update(__MODULE__,
      id: parent_id,
      action: :workflow_code_generated,
      workflow_code: code,
      session_or_message: session_or_message
    )
  end

  defp create_workflow_via_ai(assigns) do
    assigns = assign(assigns, :callbacks, build_ai_callbacks(assigns.parent_id))

    ~H"""
    <div
      class="flex-grow overflow-hidden"
      id="create_workflow_via_ai"
      phx-hook="TemplateToWorkflow"
    >
      <.live_component
        module={LightningWeb.AiAssistant.Component}
        mode={:workflow}
        can_edit={@can_edit}
        project={@project}
        user={@user}
        chat_session_id={@chat_session_id}
        code={@workflow_code}
        query_params={@query_params}
        base_url={@base_url}
        action={if(@chat_session_id, do: :show, else: :new)}
        callbacks={@callbacks}
        id={@ai_assistant_component_id}
      />
    </div>
    """
  end

  defp base_templates do
    [
      %{
        id: "base-webhook-template",
        name: "Event-based Workflow",
        description: "The basic structure for a webhook-triggered workflow",
        tags: ["webhook", "event", "workflow"],
        code: """
        name: "Event-based Workflow"
        jobs:
          Step-1:
            name: Transform data
            adaptor: "@openfn/language-common@latest"
            body: |
              // Check out the Job Writing Guide for help getting started:
              // https://docs.openfn.org/documentation/jobs/job-writing-guide
        triggers:
          webhook:
            type: webhook
            enabled: true
        edges:
          webhook->Step-1:
            source_trigger: webhook
            target_job: Step-1
            condition_type: always
            enabled: true
        """
      },
      %{
        id: "base-cron-template",
        name: "Scheduled Workflow",
        description: "The basic structure for a cron-triggered workflow",
        tags: ["cron", "scheduled", "workflow"],
        code: """
        name: "Scheduled Workflow"
        jobs:
          Get-data:
            name: Get data
            adaptor: "@openfn/language-http@7.0.3"
            body: |
              // Check out the Job Writing Guide for help getting started:
              // https://docs.openfn.org/documentation/jobs/job-writing-guide
              get('https://docs.openfn.org/documentation');
        triggers:
          cron:
            type: cron
            cron_expression: "*/15 * * * *"
            enabled: true
        edges:
          cron->Get-data:
            source_trigger: cron
            target_job: Get-data
            condition_type: always
            enabled: true
        """
      }
    ]
  end

  defp create_disabled?(assigns) do
    case assigns.selected_method do
      "import" -> !assigns.changeset.valid? or assigns.validation_failed
      "template" -> is_nil(assigns.selected_template)
      "ai" -> is_nil(assigns.workflow_code) or !assigns.changeset.valid?
    end
  end
end
