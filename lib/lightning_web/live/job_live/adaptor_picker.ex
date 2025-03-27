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
    <div class="grid grid-cols-4 md:gap-4 @container items-end">
      <div class="col-span-4 @md:col-span-2">
        <Form.label_field
          form={:adaptor_picker}
          field={:adaptor_name}
          title={"Adaptor" <> if @local_adaptors_enabled?, do: " (local)", else: ""}
          for="adaptor-name"
          tooltip="Choose an adaptor to perform operations (via helper functions) in a specific application. Pick 'http' for generic REST APIs or the 'common' adaptor if this job only performs data manipulation."
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
          {if display_name_for_adaptor(@adaptor_name) in @adaptors, do: [], else: [prompt: "---"]}
        />
      </div>
      <div :if={!@local_adaptors_enabled?} class="col-span-4 @md:col-span-2">
        <div class="flex justify-between items-center">
          <label
            for="adaptor-version"
            class="block text-sm font-medium text-secondary-700"
          >
            Version
          </label>
          <.pill
            :if={@version == "latest"}
            color="yellow"
            aria-label="Breaking changes of future versions may cause your workflow to break. Use with caution."
            phx-hook="Tooltip"
            id="latest-version-selected"
          >
            <span class="inline-block text-[0.8em] pb-[0.15em]">@</span>
            latest selected
          </.pill>
        </div>
        <.old_error field={@form[:adaptor_version]} />
        <Form.select_field
          form={@form}
          name={:adaptor}
          id="adaptor-version"
          values={@versions}
          disabled={@disabled}
        />
      </div>
      <div
        :if={display_name_for_adaptor(@adaptor_name) not in @adaptors}
        id="adaptor-not-available-warning"
        class="col-span-4 @md:col-span-2"
      >
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <.icon name="hero-exclamation-triangle" class="h-5 w-5 text-yellow-400" />
          </div>
          <div class="ml-2">
            <span class="text-xs">
              The current adaptor
              <code>
                ({@adaptor_name |> display_name_for_adaptor() |> elem(0)})
              </code>
              is not available {if @local_adaptors_enabled?,
                do: "locally",
                else: "in NPM"}
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def update(%{form: form} = params, socket) do
    {adaptor_name, version, adaptors, versions} =
      get_adaptor_version_options(Phoenix.HTML.Form.input_value(form, :adaptor))

    {:ok,
     socket
     |> assign(
       adaptor_name: adaptor_name,
       adaptor_version: Phoenix.HTML.Form.input_value(form, :adaptor),
       adaptors: adaptors,
       versions: versions,
       version: version,
       on_change: Map.get(params, :on_change),
       form: form,
       disabled: Map.get(params, :disabled, false)
     )
     |> assign_new(
       :local_adaptors_enabled?,
       fn ->
         Lightning.AdaptorRegistry.local_adaptors_enabled?()
       end
     )}
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
      {String.slice(name, 17..-1//1), name}
    else
      # Display full adaptor names for non-standard OpenFn adaptors
      name
    end
  end

  def get_adaptor_version_options(adaptor) do
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

        latest_option =
          if latest do
            [
              [
                key: "latest (≥ #{latest})",
                value: "#{module_name}@latest"
              ]
            ]
          else
            []
          end

        {module_name, version, latest_option ++ versions}
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
    # Get the latest specific version instead of using @latest
    latest_version = Lightning.AdaptorRegistry.latest_for(value)

    adaptor_value =
      if latest_version do
        "#{value}@#{latest_version}"
      else
        # fallback to @latest if no specific version found
        "#{value}@latest"
      end

    params =
      LightningWeb.Utils.build_params_for_field(
        socket.assigns.form,
        :adaptor,
        adaptor_value
      )

    socket.assigns.on_change.(params)

    {:noreply, socket}
  end
end
