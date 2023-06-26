defmodule LightningWeb.WorkflowLive.Components do
  @moduledoc false
  use LightningWeb, :component

  alias LightningWeb.Components.Form

  def workflow_list(assigns) do
    ~H"""
    <div class="w-full">
      <div class="mt-3 grid grid-cols-1 gap-5 sm:grid-cols-2 sm:gap-6 lg:grid-cols-4">
        <.create_workflow_card
          project={@project}
          can_create_workflow={@can_create_workflow}
        />
        <%= for workflow <- @workflows do %>
          <.workflow_card
            can_create_workflow={@can_create_workflow}
            can_delete_workflow={@can_delete_workflow}
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
    <div>
      <.link
        navigate={~p"/projects/#{@project.id}/w/#{@workflow.id}"}
        class="col-span-1 rounded-md shadow-sm"
        role="button"
      >
        <div class="flex flex-1 items-center justify-between truncate rounded-md border border-gray-200 bg-white hover:bg-gray-50">
          <div class="flex-1 truncate px-4 py-2 text-sm">
            <span class="font-medium text-gray-900 hover:text-gray-600">
              <%= @workflow.name %>
            </span>
            <p class="text-gray-500 text-xs">
              Created <%= Timex.Format.DateTime.Formatters.Relative.format!(
                @workflow.updated_at,
                "{relative}"
              ) %>
            </p>
          </div>
          <div class="flex-shrink-0 pr-2">
            <div
              :if={@can_delete_workflow}
              class="inline-flex h-8 w-8 items-center justify-center rounded-full bg-transparent text-gray-400 hover:text-gray-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
            >
              <.link
                href="#"
                phx-click="delete_workflow"
                phx-value-id={@workflow.id}
                data-confirm="Are you sure you'd like to delete this workflow?"
                class="inline-flex h-8 w-8 items-center justify-center rounded-full bg-transparent text-gray-400 hover:text-gray-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
              >
                <Icon.trash class="h-5 w-5 text-slate-300 hover:text-rose-700" />
              </.link>
            </div>
          </div>
        </div>
      </.link>
    </div>
    """
  end

  def create_workflow_card(assigns) do
    ~H"""
    <div>
      <.link
        navigate={~p"/projects/#{@project.id}/w/new"}
        class="col-span-1 rounded-md shadow-sm"
        role={@can_create_workflow && "button"}
      >
        <div class={"flex flex-1 items-center justify-between truncate rounded-md border border-gray-200 text-white " <> (if @can_create_workflow, do: "bg-primary-600 hover:bg-primary-700", else: "bg-gray-400")}>
          <div class="flex-1 truncate px-4 py-2 text-sm">
            <span class="font-medium">
              Create new workflow
            </span>
            <p class="text-gray-200 text-xs">Automate a process</p>
          </div>
          <div class="flex-shrink-0 pr-2">
            <div class="inline-flex h-8 w-8 items-center justify-center rounded-full bg-transparent focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2">
              <Icon.plus_circle />
            </div>
          </div>
        </div>
      </.link>
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
          <span class="inline-block mr-1">
            Create job
          </span>
          <Icon.plus_circle />
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
  attr :on_change, :any, required: true
  attr :project_user, :map, required: true

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
            on_change={@on_change}
            form={@form}
          />
        </div>
        <div class="col-span-6">
          <.live_component
            id={"credential-picker-#{input_value(@form, :id)}"}
            module={LightningWeb.JobLive.CredentialPicker}
            project_user={@project_user}
            on_change={@on_change}
            form={@form}
          />
        </div>
      </div>
    </div>
    """
  end

  def expand_job_modal(assigns) do
    ~H"""
    <div
      class="relative z-10 hidden"
      role="dialog"
      aria-modal="true"
      phx-mounted="true"
    >
      <div>I am the modal</div>
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
          |> to_string()
          |> then(fn
            "" -> "New Trigger"
            "webhook" -> "Webhook Trigger"
            "cron" -> "Cron Trigger"
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

  attr :form, :map, required: true
  attr :disabled, :boolean, required: true
  attr :cancel_url, :string, required: true

  def edge_form(assigns) do
    edge_options =
      case assigns.form.source |> Ecto.Changeset.apply_changes() do
        %{source_trigger_id: nil, source_job_id: job_id}
        when not is_nil(job_id) ->
          [
            "On Success": "on_job_success",
            "On Failure": "on_job_failure"
          ]

        %{source_trigger_id: trigger_id} when not is_nil(trigger_id) ->
          [
            Always: "always"
          ]

        _ ->
          []
      end

    assigns = assigns |> assign(:edge_options, edge_options)

    ~H"""
    <div class="h-full bg-white shadow-xl ring-1 ring-black ring-opacity-5">
      <div class="flex sticky top-0 border-b p-2">
        <div class="grow">
          Edge
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
          <Form.label_field
            form={@form}
            field={:condition}
            title="Condition"
            for={input_id(@form, :condition)}
          />
          <%= error_tag(@form, :condition,
            class: "block w-full rounded-md text-sm text-secondary-700 "
          ) %>
          <%= if input_value(@form, :condition) == :always do %>
            <Form.select_field
              form={@form}
              name={:condition}
              values={@edge_options}
              disabled={true}
            />
            <div class="max-w-xl text-sm text-gray-500">
              <p>Jobs connected to a trigger are always run.</p>
            </div>
          <% else %>
            <Form.select_field
              form={@form}
              name={:condition}
              values={@edge_options}
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
