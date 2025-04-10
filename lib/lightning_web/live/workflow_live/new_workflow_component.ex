defmodule LightningWeb.WorkflowLive.NewWorkflowComponent do
  @moduledoc false

  use LightningWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:selected_method, fn -> "import" end)}
  end

  @impl true
  def handle_event("choose-another-method", %{"method" => method}, socket) do
    {:noreply, assign(socket, selected_method: method)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-1/3">
      <div class="divide-y divide-gray-200 bg-white rounded-lg">
        <div class="flex px-4 py-5 sm:px-6">
          <div class="grow font-bold">
            Create workflow
          </div>
        </div>
        <div class="px-4 py-5 sm:p-6">
          <.create_workflow_from_scratch
            :if={@selected_method == "scratch"}
            workflow_form={@workflow_form}
            myself={@myself}
          />

          <.create_workflow_via_import
            :if={@selected_method == "import"}
            workflow_form={@workflow_form}
            myself={@myself}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :workflow_form, :map, required: true
  attr :myself, :any, required: true

  defp create_workflow_from_scratch(assigns) do
    ~H"""
    <div class="flex flex-col gap-3">
      <.form
        :let={f}
        id="new-workflow-name-form"
        for={@workflow_form}
        phx-change="validate"
      >
        <.input
          type="text"
          field={f[:name]}
          label="How do you want to name your workflow?"
        />
      </.form>
      <.button
        id="toggle_new_workflow_panel_btn"
        type="button"
        class="w-full"
        phx-click="toggle_new_workflow_panel"
        disabled={!@workflow_form.source.valid?}
      >
        Continue
      </.button>
      <div class="relative">
        <div class="absolute inset-0 flex items-center" aria-hidden="true">
          <div class="w-full border-t border-gray-300"></div>
        </div>
        <div class="relative flex justify-center">
          <span class="bg-white px-2 text-sm text-gray-500">OR</span>
        </div>
      </div>
      <.button
        id="import-workflow-btn"
        type="button"
        class="w-full inline-flex gap-x-1.5"
        phx-click="choose-another-method"
        phx-value-method="import"
        phx-target={@myself}
      >
        <.icon name="hero-document-plus" class="size-5" /> Import
      </.button>
    </div>
    """
  end

  attr :workflow_form, :map, required: true
  attr :myself, :any, required: true

  defp create_workflow_via_import(assigns) do
    ~H"""
    <div
      id="workflow-importer"
      phx-hook="YAMLToWorkflow"
      data-file-input-el="workflow-file"
      data-viewer-el="workflow-code-viewer"
      data-error-el="workflow-errors"
      class="flex flex-col gap-3"
    >
      <div class="flex justify-center rounded-lg border border-dashed border-gray-900/25 px-4 py-2">
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
      <div>
        <.textarea_element
          id="workflow-code-viewer"
          phx-update="ignore"
          name="workflow-code"
          value=""
          rows="13"
          class="font-mono proportional-nums text-slate-200 bg-slate-700 resize-none text-nowrap overflow-x-auto"
          placeholder="Paste your YAML content here"
        />
        <div id="workflow-errors" class="error-space mt-1 text-xs text-danger-600">
        </div>
      </div>
      <div class="flex flex-row justify-end gap-3">
        <.button
          id="move-back-to-scratch-btn"
          type="button"
          variant="secondary"
          phx-click="choose-another-method"
          phx-value-method="scratch"
          phx-target={@myself}
        >
          Back
        </.button>
        <.button
          id="toggle_new_workflow_panel_btn"
          type="button"
          phx-click="toggle_new_workflow_panel"
          disabled={!@workflow_form.source.valid?}
        >
          Continue
        </.button>
      </div>
    </div>
    """
  end
end
