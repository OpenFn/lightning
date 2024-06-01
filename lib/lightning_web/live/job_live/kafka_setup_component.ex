defmodule LightningWeb.JobLive.KafkaSetupComponent do
  use LightningWeb, :live_component

  alias Lightning.Workflows.Trigger.KafkaConfiguration
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
        <%
          source = KafkaConfiguration.generate_hosts_string(kafka_config.source)
          kafka_config = %{kafka_config | source: source}
        %>
        <div class="col-span-4 @md:col-span-2">
          <Form.text_field field={:hosts_string} form={kafka_config} disabled={@disabled} />
        </div>

        <div class="col-span-4 @md:col-span-2">
          <Form.text_field field={:topics} form={kafka_config} disabled={@disabled} />
        </div>

        <div class="col-span-4 @md:col-span-2">
          <Form.text_field field={:group_id} form={kafka_config} disabled={@disabled} />
        </div>
      <% end %>
    </div>
    """
  end
  #
  # defp hosts_string(kafka_config) do
  #   kafka_config.hosts
  #   |> Enum.map(&String.join(&1, ":"))
  #   |> Enum.join(", ")
  # end
end
