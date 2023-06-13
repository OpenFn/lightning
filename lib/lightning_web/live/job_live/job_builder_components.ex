defmodule LightningWeb.JobLive.JobBuilderComponents do
  use LightningWeb, :component

  alias LightningWeb.Components.Form
  import Ecto.Changeset, only: [get_field: 2]

  @start_trigger_types [
    "Cron Schedule (UTC)": "cron",
    "Webhook Event": "webhook"
  ]

  @flow_trigger_types [
    "On Job Success": "on_job_success",
    "On Job Failure": "on_job_failure"
  ]

  attr :form, :map, required: true
  attr :upstream_jobs, :list, required: true
  attr :on_cron_change, :any, required: true
  attr :disabled, :boolean, default: true

  def trigger_picker(assigns) do
    trigger_type_options =
      if get_field(assigns.form.source, :type) in [:webhook, :cron],
        do: @start_trigger_types,
        else: @flow_trigger_types

    assigns =
      assign(assigns,
        trigger_type_options: trigger_type_options,
        requires_upstream_job:
          Ecto.Changeset.get_field(assigns.form.source, :type) in [
            :on_job_failure,
            :on_job_success
          ],
        requires_cron_job:
          Ecto.Changeset.get_field(assigns.form.source, :type) == :cron,
        webhook_url: webhook_url(assigns.form.source)
      )

    ~H"""
    <div class="grid grid-cols-4 gap-4">
      <%= hidden_inputs_for(@form) %>
      <%= label @form, :type, class: "col-span-4 @md:col-span-2" do %>
        <div class="flex flex-row">
          <span class="text-sm font-medium text-secondary-700">
            Trigger
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
          values={@trigger_type_options}
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
      <%= if @requires_upstream_job do %>
        <%= label @form, :upstream_job_id, class: "block col-span-4 @md:col-span-2" do %>
          <span class="block text-sm font-medium text-secondary-700">
            Upstream Job
          </span>
          <%= error_tag(@form, :upstream_job_id, class: "block w-full rounded-md") %>
          <Form.select_field
            form={@form}
            name={:upstream_job_id}
            prompt=""
            id="upstream-job"
            values={Enum.map(@upstream_jobs, &{&1.name, &1.id})}
            disabled={@disabled}
          />
        <% end %>
      <% end %>

      <%= if @requires_cron_job do %>
        <.live_component
          id="cron-setup"
          module={LightningWeb.JobLive.CronSetupComponent}
          on_change={@on_cron_change}
          form={@form}
          disabled={@disabled}
        />
      <% end %>
    </div>
    """
  end

  defp webhook_url(changeset) do
    if get_field(changeset, :type) == :webhook do
      if id = get_field(changeset, :id) do
        Routes.webhooks_url(LightningWeb.Endpoint, :create, [id])
      end
    end
  end

  attr :changeset, :map, required: true
  attr :field, :atom, required: true
  slot :inner_block, required: true

  def when_invalid(assigns) do
    has_error =
      assigns.changeset.errors
      |> Keyword.get_values(assigns.field)
      |> Enum.any?()

    assigns = assign(assigns, has_error: has_error)

    ~H"""
    <%= if @has_error do %>
      <%= render_slot(@inner_block) %>
    <% end %>
    """
  end

  attr :adaptor, :string, required: true
  attr :disabled, :boolean, default: false
  attr :source, :string, required: true
  attr :rest, :global

  def job_editor_component(assigns) do
    assigns = assigns |> assign(disabled: assigns.disabled |> to_string())

    ~H"""
    <div
      data-adaptor={@adaptor}
      data-source={@source}
      data-disabled={@disabled}
      data-change-event="job_body_changed"
      phx-hook="JobEditor"
      phx-update="ignore"
      class="flex flex-col h-full"
      {@rest}
    >
      <!-- Placeholder while the component loads -->
      <div>
        <div class="inline-block align-middle ml-2 mr-3 text-indigo-500">
          <svg
            class="animate-spin h-5 w-5"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
          >
            <circle
              class="opacity-25"
              cx="12"
              cy="12"
              r="10"
              stroke="currentColor"
              stroke-width="4"
            >
            </circle>
            <path
              class="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
            >
            </path>
          </svg>
        </div>
        <span class="inline-block align-middle">Loading...</span>
      </div>
    </div>
    """
  end
end
