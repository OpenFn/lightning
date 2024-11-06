defmodule LightningWeb.JobLive.KafkaSetupComponent do
  use LightningWeb, :live_component

  alias Lightning.Workflows.Triggers.KafkaConfiguration

  attr :id, :string, required: true
  attr :form, :map, required: true
  attr :disabled, :boolean, required: true

  @impl true
  def render(assigns) do
    assigns =
      assign_new(assigns, :sasl_types, fn ->
        KafkaConfiguration.sasl_types() |> Enum.map(fn type -> {type, type} end)
      end)

    ~H"""
    <div id={@id} class="col-span-4 @md:col-span-2 grid grid-cols-4 gap-2">
      <div class="hidden sm:block" aria-hidden="true">
        <div class="py-2"></div>
      </div>
      <.inputs_for :let={kafka_config} field={@form[:kafka_configuration]}>
        <% source =
          kafka_config.source
          |> KafkaConfiguration.generate_hosts_string()
          |> KafkaConfiguration.generate_topics_string()

        password =
          source.changes |> Map.get(:password, Map.get(source.data, :password, ""))

        kafka_config = %{kafka_config | source: source} %>
        <div class="col-span-4 @md:col-span-2">
          <.input
            type="text"
            field={kafka_config[:hosts_string]}
            label="Hosts"
            disabled={@disabled}
          />
        </div>

        <div class="col-span-4 @md:col-span-2">
          <.input
            type="text"
            field={kafka_config[:topics_string]}
            label="Topics"
            disabled={@disabled}
          />
        </div>

        <div class="col-span-4 @md:col-span-2">
          <.input
            type="checkbox"
            field={kafka_config[:ssl]}
            label="SSL"
            disabled={@disabled}
          />
        </div>

        <div class="col-span-4 @md:col-span-2">
          <.input
            type="select"
            field={kafka_config[:sasl]}
            label="SASL Authentication"
            options={[{"none", nil}] ++ @sasl_types}
            disabled={@disabled}
          />
        </div>

        <div class="col-span-4 @md:col-span-2">
          <.input
            type="text"
            field={kafka_config[:username]}
            autocomplete="off"
            disabled={@disabled}
          />
        </div>

        <div class="col-span-4 @md:col-span-2">
          <.input
            type="password"
            field={kafka_config[:password]}
            disabled={@disabled}
            value={password}
          />
        </div>

        <div class="col-span-4 @md:col-span-2">
          <.input
            type="text"
            field={kafka_config[:initial_offset_reset_policy]}
            disabled={@disabled}
          />
        </div>

        <div class="col-span-4 @md:col-span-2">
          <.input
            type="text"
            field={kafka_config[:connect_timeout]}
            disabled={@disabled}
          />
        </div>
      </.inputs_for>
    </div>
    """
  end
end
