defmodule LightningWeb.JobLive.KafkaSetupComponent do
  use LightningWeb, :live_component

  alias Lightning.Workflows.Triggers.KafkaConfiguration
  alias LightningWeb.Components.Form

  attr :id, :string, required: true
  attr :form, :map, required: true
  attr :disabled, :boolean, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="col-span-4 @md:col-span-2 grid grid-cols-4 gap-2">
      <div class="hidden sm:block" aria-hidden="true">
        <div class="py-2"></div>
      </div>
      <%= Phoenix.HTML.Form.inputs_for @form, :kafka_configuration, fn kafka_config -> %>
        <% sasl_types =
          KafkaConfiguration.sasl_types()
          |> Enum.map(fn type -> {type, type} end)

        source =
          kafka_config.source
          |> KafkaConfiguration.generate_hosts_string()
          |> KafkaConfiguration.generate_topics_string()

        password =
          source.changes |> Map.get(:password, Map.get(source.data, :password, ""))

        kafka_config = %{kafka_config | source: source} %>
        <div class="col-span-4 @md:col-span-2">
          <Form.text_field
            field={:hosts_string}
            form={kafka_config}
            label="Hosts"
            disabled={@disabled}
          />
        </div>

        <div class="col-span-4 @md:col-span-2">
          <Form.text_field
            field={:topics_string}
            form={kafka_config}
            label="Topics"
            disabled={@disabled}
          />
        </div>

        <div class="col-span-4 @md:col-span-2">
          <Form.check_box
            field={:ssl}
            form={kafka_config}
            label="SSL"
            disabled={@disabled}
          />
        </div>

        <div class="col-span-4 @md:col-span-2">
          <Form.label_field
            field={:sasl}
            form={kafka_config}
            title="SASL Authentication"
          />
          <Form.select_field
            name={:sasl}
            form={kafka_config}
            values={[{"none", nil}] ++ sasl_types}
            disabled={@disabled}
          />
        </div>

        <div class="col-span-4 @md:col-span-2">
          <Form.text_field
            field={:username}
            form={kafka_config}
            disabled={@disabled}
            autocomplete="off123Abc"
          />
        </div>

        <div class="col-span-4 @md:col-span-2">
          <Form.password_field
            id={:password}
            form={kafka_config}
            value={password}
            disabled={@disabled}
            autocomplete="new-password"
          />
        </div>

        <div class="col-span-4 @md:col-span-2">
          <Form.text_field
            field={:initial_offset_reset_policy}
            form={kafka_config}
            disabled={@disabled}
          />
        </div>

        <div class="col-span-4 @md:col-span-2">
          <Form.text_field
            field={:connect_timeout}
            form={kafka_config}
            disabled={@disabled}
          />
        </div>
      <% end %>
    </div>
    """
  end
end
