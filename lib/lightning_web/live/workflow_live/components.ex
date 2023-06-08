defmodule LightningWeb.WorkflowLive.Components do
  @moduledoc false
  use LightningWeb, :component

  alias LightningWeb.Components.Form

  def workflow_list(assigns) do
    ~H"""
    <div class="w-full">
      <div class="w-full flex flex-wrap gap-4">
        <.create_workflow_card can_create_workflow={@can_create_workflow} />
        <%= for workflow <- @workflows do %>
          <.workflow_card
            workflow={%{workflow | name: workflow.name || "Untitled"}}
            project={@project}
          />
        <% end %>
      </div>
    </div>
    """
  end

  def workflow_card(assigns) do
    ~H"""
    <div class="relative">
      <.link
        class="w-72 h-44 bg-white rounded-md border shadow flex h-full justify-center items-center font-bold mb-2 hover:bg-gray-50"
        navigate={
          Routes.project_workflow_path(
            LightningWeb.Endpoint,
            :show,
            @project.id,
            @workflow.id
          )
        }
      >
        <%= @workflow.name %>

        <%= link(
          to: "#",
          phx_click: "delete_workflow",
          phx_value_id: @workflow.id,
          data: [ confirm: "Are you sure you'd like to delete this workflow?" ],
          class: "absolute right-2 bottom-2 p-2") do %>
          <Icon.trash class="h-6 w-6 text-slate-300 hover:text-rose-700" />
        <% end %>
      </.link>
    </div>
    """
  end

  def create_workflow_card(assigns) do
    ~H"""
    <div class="w-72 h-44 bg-white rounded-md border shadow p-4 flex flex-col h-full justify-between">
      <div class="font-bold mb-2">Create a new workflow</div>
      <div class="">Create a new workflow for your organisation</div>
      <div>
        <LightningWeb.Components.Common.button
          phx-click="create_workflow"
          disabled={!@can_create_workflow}
        >
          Create a workflow
        </LightningWeb.Components.Common.button>
      </div>
    </div>
    """
  end

  attr :socket, :map, required: true
  attr :project, :map, required: true
  attr :workflow, :map, required: true
  attr :disabled, :boolean, default: true

  def create_job_panel(assigns) do
    ~H"""
    <div class="w-1/2 h-16 text-center my-16 mx-auto pt-4">
      <div class="text-sm font-semibold text-gray-500 pb-4">
        Create your first job to get started.
      </div>
      <LightningWeb.Components.Common.button
        phx-click="create_job"
        disabled={@disabled}
      >
        <div class="h-full">
          <Heroicons.plus class="h-4 w-4 inline-block" />
          <span class="inline-block align-middle">
            Create job
          </span>
        </div>
      </LightningWeb.Components.Common.button>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :encoded_project_space, :string, required: true
  attr :selected_node, :string, default: nil
  attr :base_path, :string, required: true

  def workflow_diagram(assigns) do
    ~H"""
    <div
      phx-hook="WorkflowDiagram"
      class="h-full w-full"
      id={"hook-#{@id}"}
      phx-update="ignore"
      base-path={@base_path}
      data-selected-node={@selected_node}
      data-project-space={@encoded_project_space}
    >
    </div>
    """
  end

  attr :id, :string, required: true

  def resize_component(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="JobEditorResizer"
      phx-update="ignore"
      class="h-full bg-slate-200 w-2 cursor-col-resize z-11 resize-x"
    >
    </div>
    """
  end

  attr :form, :map, required: true
  attr :cancel_url, :string, required: true

  def job_form(assigns) do
    ~H"""
    <div class="h-full bg-white shadow-xl ring-1 ring-black ring-opacity-5">
      <div class="flex sticky top-0 border-b p-2">
        <div class="grow">
          <%= @form
          |> input_value(:name)
          |> then(fn
            "" -> "Untitled Job"
            name -> name
          end) %>
        </div>
        <div class="flex-none">
          <.link patch={@cancel_url} class="justify-center hover:text-gray-500">
            <Heroicons.x_mark solid class="h-4 w-4 inline-block" />
          </.link>
        </div>
      </div>
      <div class="md:grid md:grid-cols-6 md:gap-4 p-2 @container">
        <%= hidden_inputs_for(@form) %>
        <div class="col-span-6">
          <Form.check_box form={@form} field={:enabled} />
        </div>
        <div class="col-span-6 @md:col-span-4">
          <Form.text_field form={@form} label="Job Name" field={:name} />
        </div>
        <div class="col-span-6">
          <.live_component
            id={"adaptor-picker-#{input_value(@form, :id)}"}
            module={LightningWeb.JobLive.AdaptorPicker}
            form={@form}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :cancel_url, :string, required: true
  attr :disabled, :boolean, required: true
  attr :webhook_url, :string, required: true
  attr :requires_cron_job, :boolean, required: true
  attr :on_change, :any, required: true

  def trigger_form(assigns) do
    ~H"""
    <div class="h-full bg-white shadow-xl ring-1 ring-black ring-opacity-5">
      <div class="flex sticky top-0 border-b p-2">
        <div class="grow">
          <%= @form
          |> input_value(:type)
          |> then(fn
            "" -> "Untitled Trigger"
            name -> name
          end) %>
        </div>
        <div class="flex-none">
          <.link patch={@cancel_url} class="justify-center hover:text-gray-500">
            <Heroicons.x_mark solid class="h-4 w-4 inline-block" />
          </.link>
        </div>
      </div>
      <div class="md:grid md:grid-cols-6 md:gap-4 p-2 @container">
        <%= hidden_inputs_for(@form) %>
        <div class="col-span-6 @md:col-span-4">
          <%= label @form, :type, class: "col-span-4 @md:col-span-2" do %>
            <div class="flex flex-row">
              <span class="text-sm font-medium text-secondary-700">
                Type
              </span>
              <Common.tooltip
                id="trigger-tooltip"
                title="Choose when this job should run. Select 'webhook' for realtime workflows triggered by notifications from external systems."
                class="inline-block"
              />
            </div>
            <%= error_tag(@form, :type, class: "block w-full rounded-md") %>
            <Form.select_field
              form={@form}
              name={:type}
              id="triggerType"
              values={[
                "Cron Schedule (UTC)": "cron",
                "Webhook Event": "webhook"
              ]}
              disabled={@disabled}
            />
            <%= if @webhook_url do %>
              <div class="col-span-4 @md:col-span-2 text-right text-">
                <a
                  id="copyWebhookUrl"
                  href={@webhook_url}
                  class="text-xs text-indigo-400 underline underline-offset-2 hover:text-indigo-500"
                  onclick="(function(e) {  navigator.clipboard.writeText(e.target.href); e.preventDefault(); })(event)"
                  target="_blank"
                  phx-click="copied_to_clipboard"
                >
                  Copy webhook url
                </a>
              </div>
            <% end %>
          <% end %>
          <%= if @requires_cron_job do %>
            <div class="hidden sm:block" aria-hidden="true">
              <div class="py-2"></div>
            </div>
            <.live_component
              id="cron-setup-component"
              form={@form}
              on_change={@on_change}
              module={LightningWeb.JobLive.CronSetupComponent}
              disabled={@disabled}
            />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :changeset, :map, required: true

  def workflow_name_field(assigns) do
    ~H"""
    <.form :let={f} for={@changeset} phx-submit="save" phx-change="validate">
      <div class="relative">
        <%= text_input(
          f,
          :name,
          class: "peer block w-full
            text-2xl font-bold text-secondary-900
            border-0 py-1.5 focus:ring-0",
          placeholder: "Untitled"
        ) %>
        <div
          class="absolute inset-x-0 bottom-0
                 peer-hover:border-t peer-hover:border-gray-300
                 peer-focus:border-t-2 peer-focus:border-indigo-600"
          aria-hidden="true"
        >
        </div>
      </div>
    </.form>
    """
  end
end
