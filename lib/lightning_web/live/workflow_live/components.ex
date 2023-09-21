defmodule LightningWeb.WorkflowLive.Components do
  @moduledoc false
  use LightningWeb, :component

  alias LightningWeb.Components.Form
  alias Phoenix.LiveView.JS

  def workflow_list(assigns) do
    ~H"""
    <div class="w-full">
      <div class="mt-9 grid grid-cols-1 gap-5 sm:grid-cols-2 sm:gap-6 lg:grid-cols-4">
        <.create_workflow_card
          project={@project}
          can_create_workflow={@can_create_workflow}
        />
        <%= for workflow <- @workflows do %>
          <.workflow_card
            can_delete_workflow={@can_delete_workflow}
            workflow={%{workflow | name: workflow.name || "Untitled"}}
            project={@project}
          />
        <% end %>
      </div>
    </div>
    """
  end

  attr :project, :map, required: true
  attr :can_delete_workflow, :boolean, default: false
  attr :workflow, :map, required: true

  def workflow_card(assigns) do
    assigns =
      assigns
      |> assign(
        relative_updated_at:
          Timex.Format.DateTime.Formatters.Relative.format!(
            assigns.workflow.updated_at,
            "{relative}"
          )
      )

    ~H"""
    <div>
      <div class="flex flex-1 items-center justify-between truncate rounded-md border border-gray-200 bg-white hover:bg-gray-50">
        <.link
          id={"workflow-card-#{@workflow.id}"}
          navigate={~p"/projects/#{@project.id}/w/#{@workflow.id}"}
          class="flex-1 rounded-md shadow-sm"
          role="button"
        >
          <div class="truncate px-4 py-2 text-sm">
            <span class="font-medium text-gray-900 hover:text-gray-600">
              <%= @workflow.name %>
            </span>
            <p class="text-gray-500 text-xs">
              Updated <%= @relative_updated_at %>
            </p>
          </div>
        </.link>
        <div class="flex-shrink-0 pr-2">
          <div
            :if={@can_delete_workflow}
            class="inline-flex h-8 w-8 items-center justify-center rounded-full text-gray-400 hover:text-gray-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
          >
            <.link
              href="#"
              phx-click="delete_workflow"
              phx-value-id={@workflow.id}
              data-confirm="Are you sure you'd like to delete this workflow?"
              class="inline-flex h-8 w-8 items-center justify-center rounded-full text-gray-400 hover:text-gray-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
            >
              <Icon.trash class="h-5 w-5 text-slate-300 hover:text-rose-700" />
            </.link>
          </div>
        </div>
      </div>
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
  attr :title, :string, required: true
  attr :cancel_url, :string, required: true
  slot :inner_block, required: true
  slot :header
  slot :footer

  def panel(assigns) do
    ~H"""
    <div class="absolute right-0 sm:m-4 w-full sm:w-1/2 md:w-1/3 lg:w-1/4" id={@id}>
      <div class="divide-y divide-gray-200 overflow-hidden rounded-lg bg-white shadow">
        <div class="flex px-4 py-5 sm:px-6">
          <div class="grow font-bold">
            <%= @title %>
          </div>
          <div class="flex-none">
            <.link
              phx-hook="ClosePanelViaEscape"
              patch={@cancel_url}
              class="justify-center hover:text-gray-500"
            >
              <Heroicons.x_mark solid class="h-4 w-4 inline-block" />
            </.link>
          </div>
        </div>
        <div class="px-4 py-5 sm:p-6">
          <div class="md:grid md:grid-cols-6 md:gap-4 @container">
            <div class="col-span-6">
              <%= render_slot(@inner_block) %>
            </div>
          </div>
        </div>
        <div :if={Enum.any?(@footer)} class="p-3">
          <div class="md:grid md:grid-cols-6 md:gap-4 @container">
            <div class="col-span-6">
              <%= for item <- @footer do %>
                <%= render_slot(item) %>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :on_change, :any, required: true
  attr :editable, :boolean, default: false
  attr :project_user, :map, required: true

  def job_form(assigns) do
    ~H"""
    <div class="md:grid md:grid-cols-6 md:gap-4 p-2 @container">
      <% Phoenix.HTML.Form.hidden_inputs_for(@form) %>
      <div class="col-span-6">
        <Form.check_box form={@form} field={:enabled} disabled={!@editable} />
      </div>
      <div class="col-span-6 @md:col-span-4">
        <Form.text_field
          form={@form}
          label="Job Name"
          field={:name}
          disabled={!@editable}
        />
      </div>
      <div class="col-span-6">
        <.live_component
          id={"adaptor-picker-#{Phoenix.HTML.Form.input_value(@form, :id)}"}
          module={LightningWeb.JobLive.AdaptorPicker}
          disabled={!@editable}
          on_change={@on_change}
          form={@form}
        />
      </div>
      <div class="col-span-6">
        <.live_component
          id={"credential-picker-#{Phoenix.HTML.Form.input_value(@form, :id)}"}
          module={LightningWeb.JobLive.CredentialPicker}
          disabled={!@editable}
          project_user={@project_user}
          on_change={@on_change}
          form={@form}
        />
      </div>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :cancel_url, :string, required: true
  attr :disabled, :boolean, required: true
  attr :webhook_url, :string, required: true
  attr :on_change, :any, required: true

  def trigger_form(assigns) do
    assigns =
      assign(assigns,
        type: assigns.form.source |> Ecto.Changeset.get_field(:type)
      )

    ~H"""
    <% Phoenix.HTML.Form.hidden_inputs_for(@form) %>
    <div class="col-span-6 @md:col-span-4">
      <%= Phoenix.HTML.Form.label @form, :type, class: "col-span-4 @md:col-span-2" do %>
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
        <.old_error field={@form[:type]} />
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
      <% end %>
      <%= case @type do %>
        <% :cron -> %>
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
        <% :webhook -> %>
          <div class="col-span-4 @md:col-span-2 text-right text-">
            <a
              id="copyWebhookUrl"
              href={@webhook_url}
              class="text-xs text-indigo-400 underline underline-offset-2 hover:text-indigo-500 cursor-pointer"
              onclick="(function(e) {  navigator.clipboard.writeText(e.target.href); e.preventDefault(); })(event)"
              target="_blank"
              phx-click="copied_to_clipboard"
            >
              Copy webhook url
            </a>
          </div>
      <% end %>
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
    <% Phoenix.HTML.Form.hidden_inputs_for(@form) %>

    <Form.label_field
      form={@form}
      field={:condition}
      title="Condition"
      for={Phoenix.HTML.Form.input_id(@form, :condition)}
    />
    <.old_error field={@form[:condition]} />
    <%= if Phoenix.HTML.Form.input_value(@form, :condition) == :always do %>
      <Form.select_field
        form={@form}
        name={:condition}
        values={@edge_options}
        disabled={true}
      />
      <div class="max-w-xl text-sm text-gray-500 mt-2">
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
    """
  end

  attr :form, :map, required: true

  def workflow_name_field(assigns) do
    ~H"""
    <.form
      :let={f}
      for={@form}
      class="grow"
      phx-submit="save"
      phx-change="validate"
      id="workflow_name_form"
    >
      <div class="relative grow">
        <div class="flex items-center">
          <.text_input form={f} has_errors={f.errors[:name]} />
          <%= if f.errors[:name] do %>
            <span class="text-sm text-red-600 font-normal mx-2 px-2 py-2 rounded whitespace-nowrap z-10">
              <Icon.exclamation_circle class="h-5 w-5 inline-block" />
              <%= error_to_string(f.errors[:name]) %>
            </span>
          <% end %>
        </div>
      </div>
    </.form>
    """
  end

  defp text_input(assigns) do
    base_classes =
      ~w(block w-full rounded-md border-0 py-1.5 text-gray-900 shadow-sm ring-1
        ring-inset ring-gray-300 placeholder:text-gray-400 focus:ring-2
        focus:ring-inset focus:ring-indigo-600 sm:text-sm sm:leading-6 peer)

    classes =
      if assigns.has_errors,
        do:
          base_classes ++ ~w(bg-red-100 ring-1 ring-red-600 focus:ring-red-600),
        else: base_classes ++ ~w(focus:ring-gray-500)

    assigns = Map.put_new(assigns, :classes, classes)

    ~H"""
    <div class="relative w-full max-w-sm rounded-md shadow-sm">
      <%= Phoenix.HTML.Form.text_input(
        @form,
        :name,
        class: @classes,
        required: true,
        placeholder: "Untitled"
      ) %>
      <div class="pointer-events-none absolute inset-y-0 right-0 flex
      items-center pr-3 peer-focus:invisible">
        <Icon.pencil solid class="h-4 w-4 text-gray-400" />
      </div>
    </div>
    """
  end

  defp error_to_string({message, _}) when is_binary(message), do: message
  defp error_to_string(errors) when is_list(errors), do: Enum.join(errors, ", ")

  slot :inner_block, required: true
  attr :class, :string, default: ""
  attr :id, :string, required: true
  attr :panel_title, :string, required: true

  def collapsible_panel(assigns) do
    ~H"""
    <div
      id={@id}
      lv-keep-class
      class={["w-full flex flex-col p-4 collapsible-panel", @class]}
    >
      <div class="flex-0">
        <div
          id={"#{@id}-panel-header"}
          class="flex justify-between items-center panel-header"
        >
          <div
            id={"#{@id}-panel-header-title"}
            class="text-center font-semibold text-secondary-700 mb-2 panel-header-title"
          >
            <%= @panel_title %>
          </div>
          <div class="close-button">
            <a
              id={"#{@id}-panel-collapse-icon"}
              class="panel-collapse-icon"
              href="#"
              phx-click={JS.dispatch("collapse", to: "##{@id}")}
            >
              <Heroicons.minus_small class="w-10 h-10 p-2 hover:bg-gray-200 text-gray-600 rounded-lg" />
            </a>
            <a
              id={"#{@id}-panel-ezxpand-icon"}
              href="#"
              class="hidden panel-expand-icon"
              phx-click={JS.dispatch("expand-panel", to: "##{@id}")}
            >
              <Heroicons.plus class="w-10 h-10 p-2 hover:bg-gray-200 text-gray-600 rounded-lg" />
            </a>
          </div>
        </div>
      </div>
      <div
        id={"#{@id}-panel-content"}
        class="panel-content min-h-0 min-w-0 flex-1 pt-2"
      >
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end
end
