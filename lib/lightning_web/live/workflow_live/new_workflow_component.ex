defmodule LightningWeb.WorkflowLive.NewWorkflowComponent do
  @moduledoc false

  use LightningWeb, :live_component
  alias Lightning.Workflows.Workflow
  alias LightningWeb.API.ProvisioningJSON

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(selected_method: "template")
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

  def handle_event("validate-parsed-workflow", %{"workflow" => params}, socket) do
    changeset = Workflow.changeset(socket.assigns.workflow, params)

    response =
      if changeset.valid? do
        update_parent_form(params)

        %{}
      else
        ProvisioningJSON.error(%{changeset: changeset})
      end

    {:reply, response, assign(socket, changeset: changeset)}
  end

  def handle_event("template-parsed", %{"workflow" => params}, socket) do
    given_workflow_name =
      Ecto.Changeset.get_field(socket.assigns.workflow_name_changeset, :name)

    template_workflow_name = "Copy of #{socket.assigns.selected_template.name}"

    params =
      Map.put(params, "name", given_workflow_name || template_workflow_name)

    update_parent_form(params)

    {:noreply, socket}
  end

  def handle_event("validate-name", %{"workflow" => params}, socket) do
    update_parent_form(params)

    {:noreply,
     socket
     |> assign(workflow_name_changeset: workflow_name_changeset(params))}
  end

  def handle_event("select-template", %{"template_id" => template_id}, socket) do
    template =
      Enum.find(socket.assigns.templates, fn template ->
        template.id == template_id
      end)

    {:noreply,
     socket
     |> assign(selected_template: template)
     |> push_selected_template_code()}
  end

  defp apply_selected_method(socket) do
    case socket.assigns.selected_method do
      "template" ->
        base_templates = base_templates()
        default_template = hd(base_templates)

        socket
        |> assign(
          workflow_name_changeset: workflow_name_changeset(%{}),
          selected_template: default_template,
          templates: base_templates
        )
        |> push_selected_template_code()

      "import" ->
        changeset = Workflow.changeset(socket.assigns.workflow, %{})
        assign(socket, changeset: changeset)
    end
  end

  defp workflow_name_changeset(params) do
    {%{name: nil}, %{name: :string}}
    |> Ecto.Changeset.cast(params, [:name])
  end

  defp update_parent_form(params) do
    send(self(), {"form_changed", %{"workflow" => params}})
    :ok
  end

  defp push_selected_template_code(socket) do
    push_event(socket, "template_selected", %{
      template: socket.assigns.selected_template.code
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="w-1/3">
      <div class="divide-y divide-gray-200 bg-white h-full flex flex-col">
        <div class="flex px-4 py-5 sm:px-6 border-b border-gray-200">
          <div class="grow font-bold">
            Create workflow
          </div>
        </div>
        <div class="px-4 py-5 sm:p-6 flex-grow">
          <.create_workflow_from_template
            :if={@selected_method == "template"}
            myself={@myself}
            templates={@templates}
            selected_template={@selected_template}
            workflow_name_changeset={@workflow_name_changeset}
          />

          <.create_workflow_via_import
            :if={@selected_method == "import"}
            changeset={@changeset}
            myself={@myself}
          />
        </div>
        <div class="px-4 py-4 sm:p-3 flex flex-row justify-center gap-3 h-max">
          <.button
            :if={@selected_method == "import"}
            id="move-back-to-templates-btn"
            type="button"
            variant="secondary"
            phx-click="choose-another-method"
            phx-value-method="template"
            phx-target={@myself}
          >
            Back
          </.button>
          <.button
            :if={@selected_method != "import"}
            id="import-workflow-btn"
            type="button"
            class="inline-flex gap-x-1.5"
            phx-click="choose-another-method"
            phx-value-method="import"
            phx-target={@myself}
          >
            <.icon name="hero-document-plus" class="size-5" /> Import
          </.button>
          <.button
            id="toggle_new_workflow_panel_btn"
            type="button"
            phx-click="toggle_new_workflow_panel"
          >
            Get started
          </.button>
        </div>
      </div>
    </div>
    """
  end

  attr :workflow_name_changeset, :map, required: true
  attr :selected_template, :map, required: true
  attr :templates, :list, required: true
  attr :myself, :any, required: true

  defp create_workflow_from_template(assigns) do
    ~H"""
    <div
      id="create-workflow-from-template"
      phx-hook="TemplateToWorkflow"
      class="flex flex-col gap-3 h-full"
    >
      <.form
        :let={f}
        as={:workflow}
        id="new-workflow-name-form"
        phx-change="validate-name"
        phx-target={@myself}
        phx-debounce="300"
        for={@workflow_name_changeset}
      >
        <div class="grid grid-cols-1">
          <.input_element
            type="text"
            name={f[:name].name}
            placeholder="Describe your workflow in a few words here"
            class="col-start-1 row-start-1 block w-full text-gray-900 placeholder:text-gray-400 py-1.5 pr-3 pl-10"
            value={f[:name].value}
          />
          <.icon
            name="hero-magnifying-glass"
            class="pointer-events-none col-start-1 row-start-1 ml-3 size-5 self-center text-gray-400 sm:size-4"
          />
        </div>
      </.form>
      <.form
        id="choose-workflow-template-form"
        phx-change="select-template"
        phx-target={@myself}
        for={to_form(%{})}
        class="flex-grow"
      >
        <fieldset>
          <div class="grid grid-cols-1 gap-y-6 sm:grid-cols-2 sm:gap-x-4 overflow-y-auto">
            <label
              :for={template <- @templates}
              id={"template-label-#{template.id}"}
              phx-hook="Tooltip"
              aria-label={template.description}
              data-selected={"#{template.id == @selected_template.id}"}
              for={"template-input-#{template.id}"}
              class={[
                "flex cursor-pointer rounded-lg border bg-white p-4 shadow-xs focus:outline-hidden max-h-32 overflow-hidden text-ellipsis",
                if(template.id == @selected_template.id,
                  do: "border-indigo-600 border-2 ring-indigo-600",
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
              <span class="flex flex-1">
                <span class="flex flex-col">
                  <span class="block text-sm font-medium text-gray-900">
                    {template.name}
                  </span>
                  <span class="mt-1 flex items-center text-sm text-gray-500">
                    {template.description}
                  </span>
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
      <div class="flex justify-center rounded-lg border border-dashed border-gray-900/25 px-4 py-6">
        <div class="text-center">
          <div class="flex text-sm/6 text-gray-600">
            <label
              for="workflow-file"
              class="relative cursor-pointer rounded-md bg-white font-semibold text-indigo-600 focus-within:ring-2 focus-within:ring-indigo-600 focus-within:ring-offset-2 focus-within:outline-hidden hover:text-indigo-500"
            >
              <span>Upload a YAML file</span>
              <input
                id="workflow-file"
                name="workflow-file"
                type="file"
                class="sr-only"
                accept=".yml,.yaml"
                phx-update="ignore"
              />
            </label>
          </div>
          <p class="text-xs/5 text-gray-600">Accepts .yml and .yaml files</p>
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
        name: "base-webhook",
        description: "webhook triggered workflow",
        code: """
        jobs:
          New-job:
            name: New job
            adaptor: "@openfn/language-common@latest"
            body: |
              // Check out the Job Writing Guide for help getting started:
              // https://docs.openfn.org/documentation/jobs/job-writing-guide
        triggers:
          webhook:
            type: webhook
            enabled: false
        edges:
          webhook->New-job:
            source_trigger: webhook
            target_job: New-job
            condition_type: always
            enabled: true
        """
      },
      %{
        id: "base-cron-template",
        name: "base-cron",
        description: "cron triggered workflow",
        code: """
        jobs:
          New-job:
            name: New job
            adaptor: "@openfn/language-common@latest"
            body: |
              // Check out the Job Writing Guide for help getting started:
              // https://docs.openfn.org/documentation/jobs/job-writing-guide
        triggers:
          cron:
            type: cron
            cron_expression: 0 * * * *
            enabled: false
        edges:
          cron->New-job:
            source_trigger: cron
            target_job: New-job
            condition_type: always
            enabled: true
        """
      }
    ]
  end
end
