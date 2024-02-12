defmodule LightningWeb.WorkflowLive.Components do
  @moduledoc false
  use LightningWeb, :component

  alias Lightning.Workflows.Trigger
  alias LightningWeb.Components.Form
  alias Phoenix.LiveView.JS

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
    <div
      class="absolute right-0 sm:m-4 w-full sm:w-1/2 md:w-1/3 lg:w-1/4 max-h-content"
      id={@id}
    >
      <div class="divide-y divide-gray-200 rounded-lg bg-white shadow">
        <div class="flex px-4 py-5 sm:px-6">
          <div class="grow font-bold">
            <%= @title %>
          </div>
          <div class="flex-none">
            <.link
              id="close-panel"
              phx-hook="ClosePanelViaEscape"
              patch={@cancel_url}
              class="justify-center hover:text-gray-500"
            >
              <Heroicons.x_mark solid class="h-4 w-4 inline-block" />
            </.link>
          </div>
        </div>
        <div class="px-4 py-5 sm:p-6">
          <div class="md:gap-4">
            <%= render_slot(@inner_block) %>
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
      <div class="col-span-6"></div>
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

  defp sort_by_name(webhook_auth_methods) do
    webhook_auth_methods |> Enum.sort(&(&1.name < &2.name))
  end

  defp filter_scheduled_for_deletion(webhook_auth_methods) do
    webhook_auth_methods |> Enum.filter(&is_nil(&1.scheduled_deletion))
  end

  defp get_webhook_auth_methods_from_trigger(trigger) do
    trigger.webhook_auth_methods
    |> filter_scheduled_for_deletion()
    |> sort_by_name()
  end

  attr :form, :map, required: true
  attr :cancel_url, :string, required: true
  attr :disabled, :boolean, required: true
  attr :can_write_webhook_auth_method, :boolean, required: true
  attr :webhook_url, :string, required: true
  attr :on_change, :any, required: true
  attr :selected_trigger, Trigger, required: true
  attr :action, :any, required: true

  def trigger_form(%{form: form} = assigns) do
    assigns =
      assign(assigns,
        type:
          form.source
          |> Ecto.Changeset.get_field(:type),
        trigger_enabled: Map.get(form.params, "enabled", form.data.enabled)
      )

    ~H"""
    <% Phoenix.HTML.Form.hidden_inputs_for(@form) %>
    <div class="">
      <.input
        type="select"
        id="triggerType"
        field={@form[:type]}
        label="Trigger type"
        class=""
        options={[
          "Cron Schedule (UTC)": "cron",
          "Webhook Event": "webhook"
        ]}
        disabled={@disabled}
      />
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
          <div class="my-6">
            <label class="block text-sm font-semibold leading-6 text-slate-800">
              Webhook URL
            </label>
            <div class="mt-2 flex rounded-md shadow-sm">
              <input
                type="text"
                id="webhookUrlInput"
                class="block w-full flex-1 rounded-l-lg text-slate-900 disabled:bg-gray-50 disabled:text-gray-500 border border-r-0 border-secondary-300 sm:text-sm sm:leading-6"
                value={@webhook_url}
                disabled="disabled"
              />

              <button
                id="copyWebhookUrl"
                type="button"
                phx-hook="Copy"
                data-to="#webhookUrlInput"
                class="w-[100px] inline-block relative rounded-r-lg px-3 text-sm font-normal text-gray-900 border border-secondary-300 hover:bg-gray-50"
              >
                Copy URL
              </button>
            </div>
          </div>
          <div>
            <div>
              <span class="text-sm font-medium text-secondary-700">
                Webhook Authentication
              </span>
              <span class="inline-block relative cursor-pointer">
                <Common.tooltip
                  id="webhook-authentication-disabled-tooltip"
                  title="Require requests to this endpoint to use specific authentication protocols."
                  class="inline-grid"
                />
              </span>
            </div>
            <div class="text-xs">
              <%= if length(get_webhook_auth_methods_from_trigger(@selected_trigger)) == 0 do %>
                <p class="italic mt-3">
                  <span>
                    Add an extra layer of security with Webhook authentication.
                  </span>
                  <.link
                    id="addAuthenticationLink"
                    href="#"
                    class={[
                      "text-indigo-400 underline not-italic inline-flex items-center",
                      if(@action == :new or !@can_write_webhook_auth_method,
                        do: "text-gray-500 cursor-not-allowed",
                        else: ""
                      )
                    ]}
                    phx-click={show_modal("webhooks_auth_method_modal")}
                  >
                    Add authentication
                    <%= if @action == :new do %>
                      <Common.tooltip
                        id="webhook-authentication-disabled-tooltip"
                        title="You must save your changes before adding an authentication method"
                        class="inline"
                      />
                    <% end %>
                  </.link>
                </p>
              <% else %>
                <ul class="truncate w-full list-disc p-2 pl-3 mb-2 leading-relaxed">
                  <li :for={
                    auth_method <-
                      get_webhook_auth_methods_from_trigger(@selected_trigger)
                  }>
                    <%= if auth_method.name |> String.length <= 50 do %>
                      <%= auth_method.name %> (<.humanized_auth_method_type auth_method={
                        auth_method
                      } />)
                    <% else %>
                      <%= auth_method.name |> String.slice(0..50) %> ... (<.humanized_auth_method_type auth_method={
                        auth_method
                      } />)
                    <% end %>
                  </li>
                </ul>

                <div>
                  <.link
                    href="#"
                    class={[
                      "text-primary-700 underline hover:text-primary-800",
                      !@can_write_webhook_auth_method &&
                        "text-gray-500 cursor-not-allowed"
                    ]}
                    phx-click={show_modal("webhooks_auth_method_modal")}
                  >
                    Manage authentication
                  </.link>
                </div>
              <% end %>
            </div>
          </div>
      <% end %>
    </div>
    <div class="hidden sm:block" aria-hidden="true">
      <div class="py-2"></div>
    </div>
    <hr class="h-px bg-gray-200 border-0 dark:bg-gray-700 position:absolute" />
    <div class="hidden sm:block" aria-hidden="true">
      <div class="py-2"></div>
    </div>
    <Form.check_box
      form={@form}
      field={:enabled}
      label="Disable this trigger"
      disabled={@disabled}
      checked_value={false}
      unchecked_value={true}
      value={@trigger_enabled}
    />
    """
  end

  attr :auth_method, :map, required: true

  def humanized_auth_method_type(assigns) do
    assigns =
      assign(
        assigns,
        :humanized_type,
        %{
          api: "API",
          basic: "Basic"
        }
        |> Map.get(assigns.auth_method.auth_type, "")
      )

    ~H"""
    <span><%= @humanized_type %></span>
    """
  end

  attr :form, :map, required: true
  attr :disabled, :boolean, required: true
  attr :cancel_url, :string, required: true

  def edge_form(%{form: form} = assigns) do
    edge_options =
      case form.source |> Ecto.Changeset.apply_changes() do
        %{source_trigger_id: nil, source_job_id: job_id}
        when not is_nil(job_id) ->
          [
            "On Success": "on_job_success",
            "On Failure": "on_job_failure",
            Always: "always",
            "Matches a Javascript Expression": "js_expression"
          ]

        %{source_trigger_id: trigger_id} when not is_nil(trigger_id) ->
          [
            Always: "always",
            "Matches a Javascript Expression": "js_expression"
          ]

        _ ->
          []
      end

    assigns =
      assigns
      |> assign(:edge_options, edge_options)
      |> assign(
        :edge_enabled,
        Map.get(form.params, "enabled", form.data.enabled)
      )
      |> assign(
        :edge_condition,
        Map.get(
          form.params,
          "condition_type",
          Atom.to_string(form.data.condition_type)
        )
      )

    ~H"""
    <% Phoenix.HTML.Form.hidden_inputs_for(@form) %>
    <.old_error field={@form[:condition_type]} />
    <div class="grid grid-flow-row gap-4 auto-rows-max">
      <div>
        <.input
          type="select"
          label="Condition"
          field={@form[:condition_type]}
          options={@edge_options}
          disabled={@disabled}
        />
      </div>
      <%= if @edge_condition == "js_expression" do %>
        <div>
          <.input
            type="text"
            label="Condition Label"
            field={@form[:condition_label]}
            maxlength="255"
          />
        </div>
        <div>
          <.label>
            JS Expression
            <p class="font-normal text-xs text-gray-500 ">
              To match on output of last Step
            </p>
            <.input
              type="textarea"
              field={@form[:condition_expression]}
              class="h-24"
              phx-debounce="300"
              maxlength="255"
            />
          </.label>
        </div>
      <% end %>
      <%= if Phoenix.HTML.Form.input_value(@form, :source_trigger_id) do %>
        <div class="max-w-xl text-sm text-gray-500 mt-3">
          <p>This path will be active if its trigger is enabled.</p>
        </div>
      <% else %>
        <div class="mt-7 border-t flex flex-col justify-between">
          <h2 class=" flex mt-3">
            <Form.check_box
              form={@form}
              field={:enabled}
              disabled={@disabled}
              label="Disable this path"
              checked_value={false}
              unchecked_value={true}
              value={@edge_enabled}
            />
          </h2>
        </div>
      <% end %>
    </div>
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

  attr :auth_methods, :list, required: true
  attr :current_user, :map, required: true
  attr :on_row_select, :any, default: nil
  attr :row_selected?, :any
  attr :class, :string, default: ""
  attr :return_to, :string
  slot :action, doc: "the slot for showing user actions in the last table column"
  slot :linked_triggers, doc: "the slot for showing the linked triggers modal"

  def webhook_auth_methods_table(assigns) do
    assigns =
      assign(assigns,
        auth_methods:
          Lightning.Repo.preload(assigns.auth_methods, [:triggers, :project])
      )

    ~H"""
    <.table class={@class}>
      <.tr class="sm:px-6 lg:px-8">
        <.th :if={@on_row_select} class="relative px-7 sm:w-12 sm:px-6">
          <span class="sr-only">Select</span>
        </.th>
        <.th class={"min-w-[10rem] py-2.5 text-left text-sm font-normal
        text-gray-900 #{!@on_row_select && "pl-4"}"}>
          Name
        </.th>
        <.th class="min-w-[7rem] py-2.5 text-left text-sm font-normal text-gray-900">
          Type
        </.th>
        <.th class="min-w-[10rem] py-2.5 text-left text-sm font-normal text-gray-900">
          Linked Triggers
        </.th>
        <.th class="min-w-[4rem] py-2.5 text-right text-sm font-normal text-gray-900">
        </.th>
      </.tr>

      <.tr
        :for={auth_method <- @auth_methods}
        class="hover:bg-[#F2EEFD] transition-colors duration-200"
        id={auth_method.id}
        phx-hook="ShowActionsOnRowHover"
      >
        <.td :if={@on_row_select} class="relative sm:w-12 sm:px-6">
          <input
            id={"select_#{auth_method.id}"}
            phx-value-selection={to_string(!@row_selected?.(auth_method))}
            type="checkbox"
            class="absolute left-4 top-1/2 -mt-2 h-4 w-4 rounded border-gray-300 text-[#1992CC] focus:ring-indigo-600"
            phx-click={@on_row_select.(auth_method)}
            checked={@row_selected?.(auth_method)}
          />
        </.td>
        <.td class={
          "whitespace-nowrap py-2.5 text-sm text-gray-900 text-ellipsis
          overflow-hidden max-w-[15rem] pr-5 #{!@on_row_select && "pl-4"}"}>
          <%= auth_method.name %>
        </.td>
        <.td class="whitespace-nowrap text-sm text-gray-900">
          <.humanized_auth_method_type auth_method={auth_method} />
        </.td>
        <.td class="whitespace-nowrap text-sm text-gray-900">
          <%= render_slot(@linked_triggers, auth_method) %>
        </.td>
        <.td
          :if={@action != []}
          class="text-right px-4 hover-content font-normal opacity-0 transition-opacity duration-300 whitespace-nowrap"
        >
          <div :for={action <- @action} class="flex items-center inline-flex gap-x-2">
            <%= render_slot(action, auth_method) %>
          </div>
        </.td>
      </.tr>
    </.table>
    """
  end

  def create_workflow_modal(assigns) do
    ~H"""
    <.modal id="workflow_modal" width="w-full max-w-xl">
      <:title>
        <div class="flex justify-between">
          Let's get started
          <button
            phx-click={hide_modal("workflow_modal")}
            type="button"
            class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
            aria-label={gettext("close")}
          >
            <span class="sr-only">Close</span>
            <Heroicons.x_mark solid class="h-5 w-5 stroke-current" />
          </button>
        </div>
      </:title>
      <.form
        for={@form}
        id={@form.id}
        phx-change="validate_workflow"
        phx-submit="create_work_flow"
        class="mx-6"
      >
        <.input field={@form[:name]} type="text" label="Workflow Name" />
      </.form>
      <:footer class="mx-6 mt-6">
        <div class="flex gap-x-5 justify-end relative">
          <.link
            class="justify-center rounded-md bg-white px-4 py-3 text-sm font-semibold text-gray-500 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:mt-0 sm:w-auto"
            phx-click={hide_modal("workflow_modal")}
          >
            Cancel
          </.link>
          <span class="group">
            <button
              disabled={not @form.source.valid?}
              id="workflow_button"
              form={@form.id}
              type="submit"
              class=" justify-center rounded-md bg-primary-600 disabled:bg-primary-300 px-6 py-3 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 disabled:outline-0 focus:outline-2 focus:outline-indigo-600 focus:outline-offset-2 active:outlin-2 active:outline-indigo-600 active:outline-offset-2"
            >
              Create Workflow
            </button>
          </span>
        </div>
      </:footer>
    </.modal>
    """
  end
end
