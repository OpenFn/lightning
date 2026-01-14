defmodule LightningWeb.WorkflowLive.Components do
  @moduledoc false
  use LightningWeb, :component

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
      <.button theme="primary" phx-click="create_job" disabled={@disabled}>
        <div class="h-full">
          <span class="inline-block mr-1">
            Create job
          </span>
          <Icon.plus_circle />
        </div>
      </.button>
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
  attr :class, :string, default: ""
  attr :rest, :global
  slot :inner_block, required: true
  slot :header
  slot :footer

  def panel(assigns) do
    ~H"""
    <div
      class={[
        "absolute right-0 sm:m-4 w-full sm:w-1/2 md:w-1/3 lg:w-1/4 max-h-content",
        @class
      ]}
      id={@id}
      {@rest}
    >
      <div class="divide-y divide-gray-200 rounded-lg bg-white shadow">
        <div class="flex px-4 py-5 sm:px-6">
          <div class="grow font-bold">
            {@title}
          </div>
          <div class="flex-none">
            <.link
              id="close-panel"
              phx-hook="CloseNodePanelViaEscape"
              patch={@cancel_url}
              class="justify-center hover:text-gray-500"
            >
              <.icon name="hero-x-mark" class="h-4 w-4 inline-block" />
            </.link>
          </div>
        </div>
        <div class="px-4 py-5 sm:p-6">
          <div class="md:gap-4">
            {render_slot(@inner_block)}
          </div>
        </div>
        <div :if={Enum.any?(@footer)} class="p-3">
          <div class="md:grid md:grid-cols-6 md:gap-4 @container">
            <div class="col-span-6">
              <%= for item <- @footer do %>
                {render_slot(item)}
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :can_edit_run_settings, :boolean, required: true
  attr :project_concurrency_disabled, :boolean, required: true
  attr :sending_ai_message, :boolean, required: true
  attr :project_id, :string, required: true
  attr :max_concurrency, :integer, required: true
  attr :code_view_url, :string, required: true

  def workflow_settings(assigns) do
    ~H"""
    <div class="md:grid md:grid-cols-4 md:gap-4 p-2 @container">
      <div class="col-span-6 @md:col-span-4">
        <.input
          type="text"
          label="Workflow Name"
          field={@form[:name]}
          disabled={@sending_ai_message}
        />
      </div>
      <div class="col-span-6 @md:col-span-4">
        <span class="flex grow flex-col mb-3">
          <span class="text-sm font-semibold leading-6 text-gray-900">
            Workflow as YAML
          </span>
          <.link
            id="view-workflow-as-yaml-link"
            patch={@code_view_url}
            class="text-xs link"
          >
            View your workflow as YAML code
          </.link>
        </span>
      </div>

      <div class="col-span-6 @md:col-span-4">
        <span class="flex grow flex-col mb-3">
          <span class="text-sm font-semibold leading-6 text-gray-900">
            Log Output
          </span>
          <span class="text-xs text-gray-500">
            Control what's printed in run logs
          </span>
        </span>
        <div class="flex items-center justify-between">
          <span class="text-sm/6 font-medium text-gray-800">
            Allow <code>console.log()</code> usage
          </span>
          <.input
            id="toggle-workflow-logs-btn"
            type="toggle"
            field={@form[:enable_job_logs]}
            disabled={!@can_edit_run_settings || @sending_ai_message}
            tooltip={
              case {!@can_edit_run_settings, @sending_ai_message} do
                {true, _} ->
                  "You don't have permission to edit this setting."

                {false, true} ->
                  "You can't edit this setting while AI is processing."

                {false, false} ->
                  nil
              end
            }
          />
        </div>
      </div>

      <div class="col-span-6 @md:col-span-4">
        <span class="flex grow flex-col mb-3">
          <span class="text-sm font-semibold leading-6 text-gray-900">
            Concurrency
          </span>
          <span class="text-xs text-gray-500">
            Control how many of this workflow's <i>Runs</i>
            are executed at the same time
          </span>
        </span>
        <div class="flex grid-cols-3">
          <div class="mt-2">
            <.label for={@form[:concurrency].id}>
              Max Concurrency
              <Common.tooltip
                class="inline-block ml-1"
                id="max-concurrency-tooltip"
                title="Even if your project supports concurrency, you may LIMIT the number of runs that occur simultaneously for this particular workflow by setting a value here. (Leaving it blank will allow runs to be processed as fast as your resources allow.)"
              />
            </.label>
          </div>
          <div class="flex-grow" />
          <div class="w-24 flex-center">
            <.input_element
              type="number"
              name={@form[:concurrency].name}
              value={
                Phoenix.HTML.Form.normalize_value(
                  "number",
                  @form[:concurrency].value
                )
              }
              class="w-4 text-right"
              min="1"
              max={@max_concurrency}
              disabled={@project_concurrency_disabled || @sending_ai_message}
            />
          </div>
        </div>
        <div class="flex place-content-between items-center space-x-2 pt-1">
          <.errors field={@form[:concurrency]} />
          <div
            :if={
              not @project_concurrency_disabled and
                Enum.empty?(@form[:concurrency].errors)
            }
            class="text-xs text-slate-500 italic"
          >
            {case @form[:concurrency].value || "" do
              "" -> "Unlimited (up to max available)"
              1 -> "No more than one run at a time"
              value -> "No more than #{value} runs at a time"
            end}
          </div>
          <div
            :if={
              @project_concurrency_disabled and
                Enum.empty?(@form[:concurrency].errors)
            }
            class="text-xs"
          >
            <div class="italic text-gray-500 ">
              Parallel execution of runs is disabled for this project.
              This setting will have no effect. You can modify your Project Concurrency setting on the
              <.link class="link" patch={~p"/projects/#{@project_id}/settings"}>
                project setup
              </.link>
              page.
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
  attr :project, :map

  def job_form(assigns) do
    ~H"""
    <div class="-mt-6 md:grid md:grid-cols-6 md:gap-4 p-2 @container">
      <.form_hidden_inputs form={@form} />
      <div class="col-span-6"></div>
      <div class="col-span-6 @md:col-span-4">
        <.input
          type="text"
          field={@form[:name]}
          label="Job Name"
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
          project={@project}
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
  attr :on_change, :any, required: true
  attr :selected_trigger, :any, required: true
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
    <.form_hidden_inputs form={@form} />
    <div class="space-y-4">
      <.input
        type="select"
        id="triggerType"
        field={@form[:type]}
        label="Trigger type"
        class=""
        options={
          if Lightning.Config.kafka_triggers_enabled?() do
            [
              "Cron Schedule (UTC)": "cron",
              "Kafka Consumer": "kafka",
              "Webhook Event": "webhook"
            ]
          else
            [
              "Cron Schedule (UTC)": "cron",
              "Webhook Event": "webhook"
            ]
          end
        }
        disabled={@disabled}
      />
      <%= case @type do %>
        <% :cron -> %>
          <.live_component
            id="cron-setup-component"
            form={@form}
            on_change={@on_change}
            module={LightningWeb.JobLive.CronSetupComponent}
            disabled={@disabled}
          />
        <% :kafka -> %>
          <.live_component
            id="kafka-setup-component"
            form={@form}
            module={LightningWeb.JobLive.KafkaSetupComponent}
            disabled={@disabled}
          />
        <% :webhook -> %>
          <div>
            <label class="block text-sm font-semibold leading-6 text-slate-800">
              Webhook URL
            </label>
            <div class="mt-2 flex rounded-md shadow-xs">
              <input
                type="text"
                id="webhookUrlInput"
                class="block w-full flex-1 rounded-l-lg text-slate-900 disabled:bg-gray-50 disabled:text-gray-500 border border-r-0 border-secondary-300 sm:text-sm sm:leading-6"
                value={url(~p"/i/#{@form[:id].value}")}
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
                      "link not-italic inline-flex items-center",
                      if(
                        @action == :new or !@can_write_webhook_auth_method or
                          @disabled,
                        do: "text-gray-500 cursor-not-allowed",
                        else: ""
                      )
                    ]}
                    phx-click={
                      @can_write_webhook_auth_method &&
                        JS.push("show_modal",
                          value: %{target: "webhook_auth_method"}
                        )
                    }
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
                    {truncate_string(auth_method.name, 50)} (<span class="text-xs">{humanized_auth_method_type(auth_method)}</span>)
                  </li>
                </ul>

                <div>
                  <.link
                    href="#"
                    id="manageAuthenticationLink"
                    class={[
                      "text-primary-700 underline hover:text-primary-800",
                      (!@can_write_webhook_auth_method or @disabled) &&
                        "text-gray-500 cursor-not-allowed"
                    ]}
                    phx-click={
                      @can_write_webhook_auth_method &&
                        JS.push("show_modal",
                          value: %{target: "webhook_auth_method"}
                        )
                    }
                  >
                    Manage authentication
                  </.link>
                </div>
              <% end %>
            </div>
          </div>
      <% end %>
    </div>
    """
  end

  defp truncate_string(string, length) do
    if String.length(string) > length do
      String.slice(string, 0..length) <> "..."
    else
      string
    end
  end

  defp humanized_auth_method_type(auth_method) do
    case auth_method do
      %{auth_type: :api} -> "API"
      %{auth_type: :basic} -> "Basic"
      _ -> ""
    end
  end

  attr :id, :string, required: true

  def kafka_trigger_title(assigns) do
    ~H"""
    <div class="flex items-center">
      Kafka Trigger
      <span
        class="text-sm"
        id={"#{@id}-beta-tooltip"}
        phx-hook="Tooltip"
        data-allow-html="true"
        data-placement="bottom"
        aria-label="Kafka triggers are currently in beta and your Lightning administrator may disable them in the future. <a href='https://docs.openfn.org/documentation/build/triggers#known-sharp-edges-on-the-kafka-trigger-feature' target='_blank' class='link'>Learn about the sharp edges</a>"
      >
        <LightningWeb.Components.Common.beta_chip id={"#{@id}-beta"} />
      </span>
    </div>
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
    <.form_hidden_inputs form={@form} />
    <.old_error field={@form[:condition_type]} />
    <div class="grid grid-flow-row gap-4 auto-rows-max">
      <div>
        <.input
          type="text"
          label="Label"
          field={@form[:condition_label]}
          maxlength="255"
          disabled={@disabled}
        />
      </div>
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
          <.label>
            JS Expression
            <.icon
              :if={!js_expression_safe?(@form[:condition_expression].value)}
              id="edge-js-expression-unsafe-warning"
              name="hero-exclamation-circle-solid"
              class="size-5 text-yellow-600"
              phx-hook="Tooltip"
              aria-label="Warning: this expression appears to contain unsafe functions (eval, require, import, process, await) that may cause your workflow to fail"
            />
          </.label>
          <.input
            type="textarea"
            field={@form[:condition_expression]}
            class="h-24 font-mono proportional-nums text-slate-200 bg-slate-700"
            phx-debounce="300"
            maxlength="255"
            placeholder="eg: !state.error"
            disabled={@disabled}
          />
          <details class="mt-5 ml-1">
            <summary class="text-xs cursor-pointer">
              How to write expressions
            </summary>
            <div class="font-normal text-xs text-gray-500 ml-1 pl-2 border-l-2 border-grey-500">
              <p class="mb-2 mt-1">
                Use the state from the previous step to decide whether this step should run.
              </p>
              <p class="mb-2">
                Must be a single JavaScript expression with <code>state</code>
                in scope.
              </p>
              <p class="">
                Check
                <a
                  class="link"
                  href="https://docs.openfn.org/documentation/build/paths#writing-javascript-expressions-for-custom-path-conditions"
                  target="_blank"
                >
                  docs.openfn.org
                </a>
                for more details.
              </p>
            </div>
          </details>
        </div>
      <% end %>
    </div>
    """
  end

  defp js_expression_safe?(js_expr) do
    !String.match?(
      js_expr,
      ~r/(\bimport\b|\brequire\b|\bprocess\b|\bawait\b|\beval\b)/
    )
  end

  slot :inner_block, required: true
  slot :tabs, required: false
  attr :class, :string, default: ""
  attr :id, :string, required: true
  attr :panel_title, :string, default: ""
  attr :rest, :global

  def collapsible_panel(assigns) do
    ~H"""
    <div
      id={@id}
      lv-keep-class
      class={[
        "w-full flex flex-col collapsible-panel bg-slate-100 overflow-hidden",
        @class
      ]}
      {@rest}
    >
      <div
        id={"#{@id}-panel-header"}
        class="flex justify-between items-center p-2 px-4 panel-header z-50"
      >
        <div
          id={"#{@id}-panel-header-title"}
          class="text-center font-semibold text-secondary-700 panel-header-title text-xs"
        >
          <%= for tabs <- @tabs do %>
            {render_slot(tabs)}
          <% end %>
          <div>{@panel_title}</div>
        </div>
        <div class="close-button">
          <a
            id={"#{@id}-panel-collapse-icon"}
            class="panel-collapse-icon"
            href="#"
            phx-click={JS.dispatch("collapse", to: "##{@id}")}
          >
            <.icon
              name="hero-minus-circle"
              class="w-5 h-5 hover:bg-slate-400 text-slate-500"
            />
          </a>
          <a
            id={"#{@id}-panel-expand-icon"}
            href="#"
            class="hidden panel-expand-icon"
            phx-click={JS.dispatch("expand-panel", to: "##{@id}")}
          >
            <.icon
              name="hero-plus-circle"
              class="w-5 h-5 hover:bg-slate-400 text-slate-500"
            />
          </a>
        </div>
      </div>
      <div
        id={"#{@id}-panel-content"}
        class="panel-content min-h-0 min-w-0 flex-1 bg-white"
      >
        {render_slot(@inner_block)}
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
  slot :empty_state, doc: "the slot for showing an empty state"

  def webhook_auth_methods_table(assigns) do
    assigns =
      assign(assigns,
        auth_methods:
          Lightning.Repo.preload(assigns.auth_methods, [:triggers, :project])
      )

    ~H"""
    <%= if Enum.empty?(@auth_methods) do %>
      {render_slot(@empty_state)}
    <% else %>
      <.table class={@class}>
        <:header>
          <.tr>
            <.th :if={@on_row_select} class="relative px-7 sm:w-12 sm:px-6">
              <span class="sr-only">Select</span>
            </.th>
            <.th class={"min-w-[10rem] py-2.5 text-left text-sm font-normal text-gray-900 #{!@on_row_select && "pl-4"}"}>
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
        </:header>
        <:body>
          <%= for auth_method <- @auth_methods do %>
            <.tr id={auth_method.id}>
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
              <.td class={"whitespace-nowrap py-2.5 text-sm text-gray-900 text-ellipsis overflow-hidden max-w-[15rem] pr-5 #{!@on_row_select && "pl-4"}"}>
                {auth_method.name}
              </.td>
              <.td class="whitespace-nowrap text-sm text-gray-900">
                <span>{humanized_auth_method_type(auth_method)}</span>
              </.td>
              <.td class="whitespace-nowrap text-sm text-gray-900">
                {render_slot(@linked_triggers, auth_method)}
              </.td>
              <.td
                :if={@action != []}
                class="text-right px-4 hover-content font-normal whitespace-nowrap py-0.5"
              >
                <div
                  :for={action <- @action}
                  class="flex items-center inline-flex gap-x-2"
                >
                  {render_slot(action, auth_method)}
                </div>
              </.td>
            </.tr>
          <% end %>
        </:body>
      </.table>
    <% end %>
    """
  end

  attr :id, :any, required: true
  attr :on_close, JS, required: true

  attr :webhook_auth_method, Lightning.Workflows.WebhookAuthMethod,
    required: true

  def linked_triggers_for_webhook_auth_method_modal(assigns) do
    assigns =
      assign(assigns,
        webhook_auth_method:
          Lightning.Repo.preload(assigns.webhook_auth_method,
            triggers: [:workflow]
          )
      )

    ~H"""
    <.modal id={@id} show={true} on_close={@on_close}>
      <:title>
        <div class="flex justify-between">
          <span>Associated Workflow Triggers</span>
          <button
            phx-click={@on_close}
            type="button"
            class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
            aria-label={gettext("close")}
          >
            <span class="sr-only">Close</span>
            <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
          </button>
        </div>
      </:title>
      <div class="space-y-4">
        <p class="mb-4">
          You have {length(@webhook_auth_method.triggers)}
          <span class="font-semibold">Workflows</span>
          associated with the "<span class="font-semibold">My Auth</span>" authentication method:
        </p>
        <ul class="list-disc pl-5 mb-4">
          <li :for={trigger <- @webhook_auth_method.triggers} class="mb-2">
            <.link
              navigate={
                ~p"/projects/#{@webhook_auth_method.project_id}/w/#{trigger.workflow.id}?s=#{trigger.id}"
              }
              class="link"
              role="button"
              target="_blank"
            >
              {trigger.workflow.name}
            </.link>
          </li>
        </ul>
      </div>
      <:footer>
        <.button type="button" phx-click={@on_close} theme="primary">
          Close
        </.button>
      </:footer>
    </.modal>
    """
  end

  def workflow_info_banner(assigns) do
    ~H"""
    <div
      id={@id}
      class={"#{@position} w-full flex-none border-1 border-yellow-400 bg-yellow-50 p-4"}
    >
      <div class="max-w-7xl mx-auto sm:px-6 lg:px-8 flex">
        <div class="flex-shrink-0">
          <Heroicons.exclamation_triangle solid class="h-5 w-5 text-yellow-400" />
        </div>
        <div class="ml-2">
          <p class="text-sm text-yellow-700">
            {@message}
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string
  attr :class, :string, default: ""
  attr :presences, :list
  attr :prior_user, :map
  attr :current_user, :map
  attr :avatar_icon_size, :string, default: "h-5 w-5"
  attr :avatar_font_size, :string, default: "text-[9px]"

  def online_users(assigns) do
    ~H"""
    <div id={@id} class={["flex items-center gap-0", @class]}>
      <.render_user
        :for={%{user: online_user} <- @presences}
        :if={online_user.id != @current_user.id}
        id={"#{@id}-#{online_user.id}"}
        user={online_user}
        prior={@prior_user.id == online_user.id}
        avatar_icon_size={@avatar_icon_size}
        avatar_font_size={@avatar_font_size}
      />
    </div>
    """
  end

  defp render_user(assigns) do
    ~H"""
    <span
      id={@id}
      phx-hook="Tooltip"
      aria-label={"#{@user.first_name} #{@user.last_name} (#{@user.email})"}
      data-placement="right"
      class={"inline-flex #{@avatar_icon_size} items-center justify-center rounded-full border-2 #{if @prior, do: "border-green-400 bg-green-500", else: "border-gray-400 bg-gray-500"}"}
    >
      <span class={"#{@avatar_font_size} font-normal leading-none text-white"}>
        {user_name(@user)}
      </span>
    </span>
    """
  end

  defp user_name(user) do
    String.at(user.first_name, 0) <>
      if is_nil(user.last_name),
        do: "",
        else: String.at(user.last_name, 0)
  end

  attr :link_to_actions, :string, required: true

  def github_sync_successfull_flash(assigns) do
    ~H"""
    <span>
      Workflow saved and sync requested. Check the
      <.link href={@link_to_actions} target="_blank" class="link">
        GitHub actions
      </.link>
      for result
    </span>
    """
  end
end
