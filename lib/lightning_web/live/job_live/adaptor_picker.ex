defmodule LightningWeb.JobLive.AdaptorPicker do
  @moduledoc """
  Component allowing selecting an adaptor and it's version
  """

  use LightningWeb, :live_component

  alias LightningWeb.Components.Form

  attr :form, :map, required: true
  attr :on_change, :any, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grid grid-cols-4 gap-1">
      <div class="md:col-span-3">
        <Form.label_field
          form={:adaptor_picker}
          id={:adaptor_name}
          title="Adaptor"
          for="adaptor-name"
        />
        <Form.select_field
          form={:adaptor_picker}
          name={:adaptor_name}
          prompt=""
          selected={@adaptor_name}
          id="adaptor-name"
          values={@adaptors}
          phx-change="adaptor_name_change"
          phx-target={@myself}
        />
      </div>

      <div class="md:col-span-1">
        <Form.label_field
          form={@form}
          id={:adaptor}
          title="Version"
          for="adaptor-version"
        />
        <%= error_tag(@form, :adaptor,
          class: "block w-full rounded-md text-sm text-secondary-700 "
        ) %>
        <Form.select_field
          form={@form}
          disabled={!@adaptor_name}
          name={:adaptor}
          id="adaptor-version"
          values={@versions}
        />
      </div>
    </div>
    """
  end

  @impl true
  def update(%{form: form, on_change: on_change}, socket) do
    {adaptor_name, _, adaptors, versions} =
      get_adaptor_version_options(Phoenix.HTML.Form.input_value(form, :adaptor))

    {:ok,
     socket
     |> assign(:adaptor_name, adaptor_name)
     |> assign(:adaptors, adaptors)
     |> assign(:versions, versions)
     |> assign(:on_change, on_change)
     |> assign(:form, form)}
  end

  defp display_name_for_adaptor(name) do
    if String.starts_with?(name, "@openfn/language-") do
      # Show most relevant slice of the name for standard adaptors
      {String.slice(name, 17..-1), name}
    else
      # Display full adaptor names for non-standard OpenFn adaptors
      name
    end
  end

  def get_adaptor_version_options(adaptor) do
    # Gets @openfn/language-foo@1.2.3 or @openfn/language-foo

    adaptor_names =
      Lightning.AdaptorRegistry.all()
      |> Enum.map(&display_name_for_adaptor(&1.name))
      |> Enum.sort()

    {module_name, version, versions} =
      if adaptor do
        {module_name, version} =
          Lightning.AdaptorRegistry.resolve_package_name(adaptor)

        versions =
          Lightning.AdaptorRegistry.versions_for(module_name)
          |> List.wrap()
          |> Enum.map(&Map.get(&1, :version))
          |> Enum.sort_by(&Version.parse(&1), :desc)
          |> Enum.map(fn version ->
            [key: version, value: "#{module_name}@#{version}"]
          end)

        {module_name, version,
         [[key: "latest", value: "#{module_name}@latest"] | versions]}
      else
        {nil, nil, []}
      end

    {module_name, version, adaptor_names, versions}
  end

  @impl true
  def handle_event(
        "adaptor_name_change",
        %{"adaptor_picker" => %{"adaptor_name" => adaptor_name}},
        socket
      ) do
    socket.assigns.on_change.("#{adaptor_name}@latest")

    {:noreply, socket}
  end
end
