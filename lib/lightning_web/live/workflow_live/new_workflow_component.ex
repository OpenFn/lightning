defmodule LightningWeb.WorkflowLive.NewWorkflowComponent do
  @moduledoc false
  use LightningWeb, :live_component

  alias Lightning.Projects
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkflowTemplates
  alias LightningWeb.API.ProvisioningJSON

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(selected_method: "template")
     |> assign(search_term: "")
     |> apply_selected_method()}
  end

  @impl true
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
    {:noreply,
     socket |> assign(selected_method: method) |> apply_selected_method()}
  end

  def handle_event("search-templates", %{"search" => search_term}, socket) do
    filtered_templates =
      filter_templates(socket.assigns.users_templates, search_term)

    {:noreply,
     socket
     |> assign(search_term: search_term)
     |> assign(filtered_templates: filtered_templates)}
  end

  def handle_event(
        "select-template",
        %{"template_id" => template_id} = _params,
        socket
      ) do
    template =
      Enum.find(socket.assigns.all_templates, fn template ->
        template.id == template_id
      end)

    {:noreply,
     socket
     |> assign(selected_template: template)
     |> push_selected_template_code()}
  end

  def handle_event(event_name, %{"workflow" => params}, socket)
      when event_name in ["workflow-parsed", "template-parsed"] do
    %{project: project, selected_template: template} = socket.assigns

    workflow_name = default_if_empty(params["name"], "Untitled Workflow")
    template_name = default_if_empty(template.name, "Untitled Template")

    params =
      project
      |> Projects.list_workflows()
      |> generate_workflow_name(
        workflow_name,
        template_name,
        event_name
      )
      |> then(fn name -> Map.put(params, "name", name) end)

    update_parent_form(params)

    case event_name do
      "workflow-parsed" -> handle_workflow_parsed(socket, params)
      "template-parsed" -> handle_template_parsed(socket, params)
    end
  end

  defp default_if_empty(name, default) do
    if String.trim(name || "") == "", do: default, else: name
  end

  defp generate_workflow_name(
         existing_workflows,
         workflow_name,
         template_name,
         event_name
       ) do
    base_name =
      "Copy of " <>
        case event_name do
          "workflow-parsed" -> workflow_name
          "template-parsed" -> template_name
        end

    generate_unique_name(base_name, existing_workflows)
  end

  defp handle_workflow_parsed(socket, params) do
    changeset = Workflow.changeset(socket.assigns.workflow, params)

    if changeset.valid? do
      {:reply, %{},
       socket
       |> update_workflow_canvas(params)
       |> assign(changeset: changeset)}
    else
      {:reply, ProvisioningJSON.error(%{changeset: changeset}),
       assign(socket, changeset: changeset)}
    end
  end

  defp handle_template_parsed(socket, params) do
    {:noreply, update_workflow_canvas(socket, params)}
  end

  defp generate_unique_name(base_name, existing_workflows) do
    existing_names = MapSet.new(existing_workflows, & &1.name)

    Stream.iterate(0, &(&1 + 1))
    |> Enum.reduce_while(base_name, fn i, name ->
      candidate = if i == 0, do: name, else: "#{name} #{i}"

      if MapSet.member?(existing_names, candidate) do
        {:cont, name}
      else
        {:halt, candidate}
      end
    end)
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

  defp apply_selected_method(socket) do
    case socket.assigns.selected_method do
      "template" ->
        base_templates = base_templates()
        users_templates = WorkflowTemplates.list_templates()
        all_templates = base_templates ++ users_templates
        default_template = hd(base_templates)

        socket
        |> assign(
          selected_template: default_template,
          base_templates: base_templates,
          users_templates: users_templates,
          filtered_templates: users_templates,
          all_templates: all_templates
        )
        |> push_selected_template_code()

      "import" ->
        changeset = Workflow.changeset(socket.assigns.workflow, %{})
        assign(socket, changeset: changeset)
    end
  end

  def update_parent_form(params) do
    send(
      self(),
      {"form_changed", %{"workflow" => params, "opts" => [push_patches: false]}}
    )

    :ok
  end

  defp push_selected_template_code(socket) do
    push_event(socket, "template_selected", %{
      template: socket.assigns.selected_template.code
    })
  end

  defp update_workflow_canvas(socket, params) do
    socket
    |> push_event("state-applied", %{"state" => params})
    |> push_event("force-fit", %{})
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        templates:
          Enum.sort_by(
            assigns.base_templates ++ assigns.filtered_templates,
            & &1.name
          )
      )

    ~H"""
    <div id={@id} class="w-1/3">
      <div class="divide-y divide-gray-200 bg-white h-full flex flex-col">
        <div class="px-2 py-2 sm:px-4 sm:py-2 flex-grow overflow-hidden flex flex-col">
          <.create_workflow_from_template
            :if={@selected_method == "template"}
            myself={@myself}
            templates={@templates}
            selected_template={@selected_template}
            search_term={@search_term}
          />

          <.create_workflow_via_import
            :if={@selected_method == "import"}
            changeset={@changeset}
            myself={@myself}
          />
        </div>
        <div class="px-4 py-4 sm:p-3 flex flex-row justify-center gap-3 h-max border-t">
          <.button
            :if={@selected_method != "import"}
            id="import-workflow-btn"
            type="button"
            theme="primary"
            class="inline-flex gap-x-1.5"
            phx-click="choose-another-method"
            phx-value-method="import"
            phx-target={@myself}
          >
            <.icon name="hero-document" class="size-5" /> Import
          </.button>
          <.button
            :if={@selected_method != "import"}
            id="toggle_new_workflow_panel_btn"
            type="button"
            theme="primary"
            phx-click="toggle_new_workflow_panel"
          >
            Get started
          </.button>
          <.button
            :if={@selected_method == "import"}
            id="move-back-to-templates-btn"
            type="button"
            theme="secondary"
            phx-click="choose-another-method"
            phx-value-method="template"
            phx-target={@myself}
          >
            Back
          </.button>
          <.button
            :if={@selected_method == "import"}
            id="toggle_new_workflow_panel_btn"
            type="button"
            phx-click="toggle_new_workflow_panel"
            disabled={!@changeset.valid?}
            theme="primary"
          >
            Get started
          </.button>
        </div>
      </div>
    </div>
    """
  end

  attr :selected_template, :map, required: true
  attr :templates, :list, required: true
  attr :myself, :any, required: true
  attr :search_term, :string, required: true

  defp create_workflow_from_template(assigns) do
    ~H"""
    <div
      id="create-workflow-from-template"
      phx-hook="TemplateToWorkflow"
      class="flex flex-col p-1 gap-4 h-full overflow-hidden"
    >
      <div>
        <h3 class="text-base font-medium text-gray-700 mb-4">
          Build your workflow from templates
        </h3>
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
              placeholder="Browse templates"
              class="block w-full rounded-md border-0 py-2 pl-10 pr-4 text-gray-900 ring-1 ring-gray-300 focus:ring-2 focus:ring-indigo-600 sm:text-sm"
              value={@search_term}
            />
            <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
              <.icon name="hero-magnifying-glass" class="size-5 text-gray-400" />
            </div>
          </div>
        </.form>
      </div>

      <.form
        id="choose-workflow-template-form"
        phx-change="select-template"
        phx-target={@myself}
        for={to_form(%{})}
        class="flex-grow mt-2 overflow-hidden flex flex-col"
      >
        <fieldset class="overflow-auto flex-grow">
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <label
              :for={template <- @templates}
              id={"template-label-#{template.id}"}
              phx-hook="Tooltip"
              aria-label={"<span class='font-medium text-left text-sm text-white block mb-2'>#{template.name}</span><span class='text-gray-300 text-xs block text-left'>#{template.description}</span>"}
              data-allow-html="true"
              data-selected={"#{template.id == @selected_template.id}"}
              for={"template-input-#{template.id}"}
              class={[
                "relative flex flex-col cursor-pointer rounded-lg border bg-white p-4 hover:bg-gray-50 transition-all h-24",
                if(template.id == @selected_template.id,
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
      class="flex flex-col gap-3 h-full"
    >
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
        <div
          id="workflow-errors"
          class="error-space mb-1 text-xs text-danger-600 hidden"
        >
        </div>
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

  defp base_templates do
    [
      %{
        id: "base-webhook-template",
        name: "Event-based Workflow",
        description: "The basic structure for a webhook-triggered workflow",
        tags: ["webhook", "event", "workflow"],
        code: """
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
            enabled: false
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
            enabled: false
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
end
