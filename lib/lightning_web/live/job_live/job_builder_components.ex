defmodule LightningWeb.JobLive.JobBuilderComponents do
  use LightningWeb, :component

  alias LightningWeb.Components.Form
  import Ecto.Changeset, only: [get_field: 2]

  @trigger_type_options [
    Cron: "cron",
    Webhook: "webhook",
    "On Job Success": "on_job_success",
    "On Job Failure": "on_job_failure"
  ]

  attr :form, :map, required: true
  attr :upstream_jobs, :list, required: true
  attr :on_cron_change, :any, required: true

  def trigger_picker(assigns) do
    assigns =
      assign(assigns,
        trigger_type_options: @trigger_type_options,
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
    <%= hidden_inputs_for(@form) %>
    <%= label @form, :type, class: "block" do %>
      <span class="block text-sm font-medium text-secondary-700">
        Trigger
      </span>
      <%= error_tag(@form, :type, class: "block w-full rounded-md") %>
      <Form.select_field
        form={@form}
        name={:type}
        prompt=""
        id="triggerType"
        values={@trigger_type_options}
      />
    <% end %>
    <%= if @webhook_url do %>
      <a
        id="copyWebhookUrl"
        href={@webhook_url}
        onclick="(function(e) {  navigator.clipboard.writeText(e.target.href); e.preventDefault(); })(event)"
        target="_blank"
      >
        Copy webhook url
      </a>
    <% end %>

    <%= if @requires_upstream_job do %>
      <%= label @form, :upstream_job_id, class: "block" do %>
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
        />
      <% end %>
    <% end %>

    <%= if @requires_cron_job do %>
      <.live_component
        id="cron-setup"
        module={LightningWeb.JobLive.CronSetupComponent}
        on_change={@on_cron_change}
        form={@form}
      />
    <% end %>
    """
  end

  defp webhook_url(changeset) do
    if get_field(changeset, :type) == :webhook do
      if id = get_field(changeset, :id) do
        Routes.webhooks_url(LightningWeb.Endpoint, :create, [id])
      end
    end
  end

  attr :for_hash, :string, required: true
  slot :inner_block, required: true

  def panel_content(assigns) do
    ~H"""
    <div x-show={"tab === '#{@for_hash}'"}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  attr :hash, :string, required: true
  slot :inner_block, required: true

  def tab_item(assigns) do
    ~H"""
    <a
      id={"tab-item-#{@hash}"}
      class="whitespace-nowrap flex items-center py-3 px-3 border-b-2 font-medium text-sm"
      x-bind:class={"tab === '#{@hash}' ? 'border-primary-500 text-primary-600 dark:text-primary-500 dark:border-primary-500' : 'border-transparent text-gray-500 dark:hover:text-gray-300 dark:text-gray-400 hover:border-gray-300 hover:text-gray-600 hover:border-gray-300'"}
      @click.prevent={"tab = '#{@hash}'; window.location.hash = '#{@hash}'"}
      href="#"
    >
      <%= render_slot(@inner_block) %>
    </a>
    """
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

  def compiler_component(assigns) do
    ~H"""
    <div
      data-adaptor={@adaptor}
      phx-hook="Compiler"
      phx-update="ignore"
      id="compiler-component"
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
