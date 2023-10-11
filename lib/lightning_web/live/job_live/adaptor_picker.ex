defmodule LightningWeb.JobLive.AdaptorPicker do
  @moduledoc """
  Component allowing selecting an adaptor and it's version
  """

  use LightningWeb, :live_component

  alias LightningWeb.Components.Form

  attr :form, :map, required: true
  attr :on_change, :any, default: nil
  attr :disabled, :boolean, default: false

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grid grid-cols-4 gap-2 @container">
      <div class="col-span-4 @md:col-span-2">
        <Form.label_field
          form={:adaptor_picker}
          field={:adaptor_name}
          title="Adaptor"
          for="adaptor-name"
          tooltip="Choose an adaptor to perform operations (via helper functions) in a specific application. Pick ‘http’ for generic REST APIs or the 'common' adaptor if this job only performs data manipulation."
        />
        <Form.select_field
          form={:adaptor_picker}
          name={:adaptor_name}
          selected={@adaptor_name}
          id="adaptor-name"
          values={@adaptors}
          phx-change="adaptor_name_change"
          phx-target={@myself}
          disabled={@disabled}
        />
      </div>
      <div class="col-span-4 @md:col-span-2">
        <Form.label_field
          form={@form}
          field={:adaptor_version}
          title="Version"
          for="adaptor-version"
        />
        <.old_error field={@form[:adaptor_version]} />
        <Form.select_field
          form={@form}
          name={:adaptor}
          id="adaptor-version"
          values={@versions}
          disabled={@disabled}
        />
      </div>
    </div>
    """
  end

  @impl true
  def update(%{form: form} = params, socket) do
    {adaptor_name, _version, adaptors, versions} =
      get_adaptor_version_options(Phoenix.HTML.Form.input_value(form, :adaptor))

    {:ok,
     socket
     |> assign(:adaptor_name, adaptor_name)
     |> assign(:adaptor_version, Phoenix.HTML.Form.input_value(form, :adaptor))
     |> assign(:adaptors, adaptors)
     |> assign(:versions, versions)
     |> assign(:on_change, Map.get(params, :on_change))
     |> assign(:form, form)
     |> assign(:disabled, Map.get(params, :disabled, false))}
  end

  @doc """
  Converts standard adaptor names into "label","value" lists and returns
  non-standard names as merely "value"; both can be passed directly into a
  select option list.
  """
  @spec display_name_for_adaptor(String.t()) ::
          String.t() | {String.t(), String.t()}
  def display_name_for_adaptor(name) do
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

        latest = Lightning.AdaptorRegistry.latest_for(module_name)

        versions =
          Lightning.AdaptorRegistry.versions_for(module_name)
          |> List.wrap()
          |> Enum.map(&Map.get(&1, :version))
          |> Enum.sort_by(&Version.parse(&1), :desc)
          |> Enum.map(fn version ->
            build_select_option(module_name, version)
          end)

        key =
          if latest do
            "latest (≥ #{latest})"
          else
            ""
          end

        {module_name, version,
         [[key: key, value: "#{module_name}@latest"] | versions]}
      else
        {nil, nil, []}
      end

    {module_name, version, adaptor_names, versions}
  end

  defp build_select_option(module_name, version) do
    [key: version, value: "#{module_name}@#{version}"]
  end

  @impl true
  def handle_event(
        "adaptor_name_change",
        %{"adaptor_picker" => %{"adaptor_name" => value}},
        socket
      ) do
    params =
      LightningWeb.Utils.build_params_for_field(
        socket.assigns.form,
        :adaptor,
        "#{value}@latest"
      )

    socket.assigns.on_change.(params)

    {:noreply, socket}
  end
end
